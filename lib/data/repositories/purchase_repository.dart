import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/invoice_number.dart';
import '../models/purchase.dart';
import '../database/db_helper.dart';

class PurchaseWithItems {
  final Purchase purchase;
  final List<PurchaseItem> items;

  PurchaseWithItems({required this.purchase, required this.items});
}

class PurchaseRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Fetches all active purchases (newest first)
  Future<List<Purchase>> getPurchases() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'purchases',
      where: 'is_deleted = 0',
      orderBy: 'date DESC, created_at DESC',
    );
    return List.generate(maps.length, (i) => Purchase.fromMap(maps[i]));
  }

  /// Fetches a specific purchase and its line items
  Future<PurchaseWithItems?> getPurchase(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> purchaseMaps = await db.query(
      'purchases',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (purchaseMaps.isEmpty) return null;

    final Purchase purchase = Purchase.fromMap(purchaseMaps.first);

    final List<Map<String, dynamic>> itemMaps = await db.query(
      'purchase_items',
      where: 'purchase_id = ?',
      whereArgs: [id],
    );

    final List<PurchaseItem> items = List.generate(
      itemMaps.length,
      (i) => PurchaseItem.fromMap(itemMaps[i]),
    );

    return PurchaseWithItems(purchase: purchase, items: items);
  }

  /// Generates the next sequential invoice number for purchases
  Future<String> getNextInvoiceNumber(DateTime date) async {
    final db = await _dbHelper.database;
    final String fy = AppDateUtils.getFinancialYear(date);
    final String prefix = 'PUR/$fy/';

    // We check all invoices (even deleted ones) to ensure uniqueness
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT invoice_no FROM purchases
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
      type: 'PUR',
      financialYear: fy,
      sequenceNumber: maxSequence + 1,
    );
  }

  /// Inserts a new purchase transaction
  Future<void> insertPurchase(Purchase purchase, List<PurchaseItem> items, String deviceId) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      // 1. Insert Purchase
      final purchaseMap = purchase.toMap();
      await txn.insert('purchases', purchaseMap);

      // 2. Insert line items
      final List<Map<String, dynamic>> itemsList = [];
      for (final item in items) {
        final itemMap = item.toMap();
        await txn.insert('purchase_items', itemMap);
        itemsList.add(itemMap);
      }

      final payload = {
        'purchase': purchaseMap,
        'items': itemsList,
      };

      // 3. Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'purchases',
        'record_id': purchase.id,
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
        'table_name': 'purchases',
        'record_id': purchase.id,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Updates a purchase transaction and logs its change history
  Future<void> updatePurchase(Purchase purchase, List<PurchaseItem> items, String deviceId) async {
    final db = await _dbHelper.database;
    
    final currentData = await getPurchase(purchase.id);
    if (currentData == null) return;

    final oldPayload = {
      'purchase': currentData.purchase.toMap(),
      'items': currentData.items.map((e) => e.toMap()).toList(),
    };

    // Append edit details to history
    final List<dynamic> history = List.from(currentData.purchase.editHistory);
    history.add({
      'timestamp': DateTime.now().toIso8601String(),
      'device_id': deviceId,
      'old_grand_total': currentData.purchase.grandTotal,
      'new_grand_total': purchase.grandTotal,
    });

    final updatedPurchase = purchase.copyWith(editHistory: history, updatedAt: DateTime.now());
    final purchaseMap = updatedPurchase.toMap();

    await db.transaction((txn) async {
      // 1. Update purchase row
      await txn.update(
        'purchases',
        purchaseMap,
        where: 'id = ?',
        whereArgs: [purchase.id],
      );

      // 2. Delete old items
      await txn.delete(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [purchase.id],
      );

      // 3. Insert new items
      final List<Map<String, dynamic>> itemsList = [];
      for (final item in items) {
        final itemMap = item.toMap();
        await txn.insert('purchase_items', itemMap);
        itemsList.add(itemMap);
      }

      final newPayload = {
        'purchase': purchaseMap,
        'items': itemsList,
      };

      // 4. Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'purchases',
        'record_id': purchase.id,
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
        'table_name': 'purchases',
        'record_id': purchase.id,
        'payload': jsonEncode(newPayload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Soft deletes a purchase (retained in recycle bin for 30 days)
  Future<void> deletePurchase(String id, String deviceId) async {
    final db = await _dbHelper.database;
    final currentData = await getPurchase(id);
    if (currentData == null) return;

    final oldPayload = {
      'purchase': currentData.purchase.toMap(),
      'items': currentData.items.map((e) => e.toMap()).toList(),
    };

    final updatedPurchase = currentData.purchase.copyWith(
      isDeleted: true,
      updatedAt: DateTime.now(),
    );
    final newPayload = {
      'purchase': updatedPurchase.toMap(),
      'items': currentData.items.map((e) => e.toMap()).toList(),
    };

    await db.transaction((txn) async {
      await txn.update(
        'purchases',
        {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'purchases',
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
        'table_name': 'purchases',
        'record_id': id,
        'payload': jsonEncode(newPayload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }
}
