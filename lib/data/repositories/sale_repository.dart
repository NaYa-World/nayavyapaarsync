import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/invoice_number.dart';
import '../models/sale.dart';
import '../database/db_helper.dart';

class SaleWithItems {
  final Sale sale;
  final List<SaleItem> items;

  SaleWithItems({required this.sale, required this.items});
}

class SaleRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Fetches all active sales (newest first)
  Future<List<Sale>> getSales() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sales',
      where: 'is_deleted = 0',
      orderBy: 'date DESC, created_at DESC',
    );
    return List.generate(maps.length, (i) => Sale.fromMap(maps[i]));
  }

  /// Fetches a specific sale and its line items
  Future<SaleWithItems?> getSale(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> saleMaps = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (saleMaps.isEmpty) return null;

    final Sale sale = Sale.fromMap(saleMaps.first);

    final List<Map<String, dynamic>> itemMaps = await db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [id],
    );

    final List<SaleItem> items = List.generate(
      itemMaps.length,
      (i) => SaleItem.fromMap(itemMaps[i]),
    );

    return SaleWithItems(sale: sale, items: items);
  }

  /// Generates the next sequential invoice number for sales
  Future<String> getNextInvoiceNumber(DateTime date) async {
    final db = await _dbHelper.database;
    final String fy = AppDateUtils.getFinancialYear(date);
    final String prefix = 'SAL/$fy/';

    // We check all invoices (even deleted ones) to ensure uniqueness
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT invoice_no FROM sales
      WHERE invoice_no LIKE ?
    ''', ['$prefix%']);

    int maxSequence = 0;
    for (final row in result) {
      final String invoiceNo = row['invoice_no'] as String;
      final parsed = InvoiceNumberGenerator.parse(invoiceNo);
      if (parsed != null) {
        final int seq = parsed['sequence'] as int;
        if (seq > maxSequence) {
          maxSequence = seq;
        }
      }
    }

    return InvoiceNumberGenerator.generate(
      type: 'SAL',
      financialYear: fy,
      sequenceNumber: maxSequence + 1,
    );
  }

  /// Inserts a new sale transaction
  Future<void> insertSale(Sale sale, List<SaleItem> items, String deviceId) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      // 1. Insert Sale
      final saleMap = sale.toMap();
      await txn.insert('sales', saleMap);

      // 2. Insert line items
      final List<Map<String, dynamic>> itemsList = [];
      for (final item in items) {
        final itemMap = item.toMap();
        await txn.insert('sale_items', itemMap);
        itemsList.add(itemMap);
      }

      final payload = {
        'sale': saleMap,
        'items': itemsList,
      };

      // 3. Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'sales',
        'record_id': sale.id,
        'action': 'CREATE',
        'old_values': null,
        'new_values': jsonEncode(payload),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // 4. Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'CREATE',
        'table_name': 'sales',
        'record_id': sale.id,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Updates a sale transaction and logs its change history
  Future<void> updateSale(Sale sale, List<SaleItem> items, String deviceId) async {
    final db = await _dbHelper.database;
    
    final currentData = await getSale(sale.id);
    if (currentData == null) return;

    final oldPayload = {
      'sale': currentData.sale.toMap(),
      'items': currentData.items.map((e) => e.toMap()).toList(),
    };

    // Append edit details to history
    final List<dynamic> history = List.from(currentData.sale.editHistory);
    history.add({
      'timestamp': DateTime.now().toIso8601String(),
      'device_id': deviceId,
      'old_grand_total': currentData.sale.grandTotal,
      'new_grand_total': sale.grandTotal,
    });

    final updatedSale = sale.copyWith(editHistory: history, updatedAt: DateTime.now());
    final saleMap = updatedSale.toMap();

    await db.transaction((txn) async {
      // 1. Update sale row
      await txn.update(
        'sales',
        saleMap,
        where: 'id = ?',
        whereArgs: [sale.id],
      );

      // 2. Delete old items
      await txn.delete(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [sale.id],
      );

      // 3. Insert new items
      final List<Map<String, dynamic>> itemsList = [];
      for (final item in items) {
        final itemMap = item.toMap();
        await txn.insert('sale_items', itemMap);
        itemsList.add(itemMap);
      }

      final newPayload = {
        'sale': saleMap,
        'items': itemsList,
      };

      // 4. Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'sales',
        'record_id': sale.id,
        'action': 'EDIT',
        'old_values': jsonEncode(oldPayload),
        'new_values': jsonEncode(newPayload),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // 5. Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'EDIT',
        'table_name': 'sales',
        'record_id': sale.id,
        'payload': jsonEncode(newPayload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Soft deletes a sale (retained in recycle bin for 30 days)
  Future<void> deleteSale(String id, String deviceId) async {
    final db = await _dbHelper.database;
    final currentData = await getSale(id);
    if (currentData == null) return;

    final oldPayload = {
      'sale': currentData.sale.toMap(),
      'items': currentData.items.map((e) => e.toMap()).toList(),
    };

    final updatedSale = currentData.sale.copyWith(
      isDeleted: true,
      updatedAt: DateTime.now(),
    );
    final newPayload = {
      'sale': updatedSale.toMap(),
      'items': currentData.items.map((e) => e.toMap()).toList(),
    };

    await db.transaction((txn) async {
      await txn.update(
        'sales',
        {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'sales',
        'record_id': id,
        'action': 'DELETE',
        'old_values': jsonEncode(oldPayload),
        'new_values': jsonEncode(newPayload),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'DELETE',
        'table_name': 'sales',
        'record_id': id,
        'payload': jsonEncode(newPayload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }
}
