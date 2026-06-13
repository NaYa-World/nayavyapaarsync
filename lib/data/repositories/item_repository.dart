import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/item.dart';
import '../database/db_helper.dart';

class StockMovement {
  final String transactionId;
  final String invoiceNo;
  final String type; // 'PURCHASE' or 'SALE'
  final String partyName;
  final DateTime date;
  final double qty; // positive for purchase, negative for sale
  final double rate;
  final double runningStock;

  StockMovement({
    required this.transactionId,
    required this.invoiceNo,
    required this.type,
    required this.partyName,
    required this.date,
    required this.qty,
    required this.rate,
    required this.runningStock,
  });
}

class ItemRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Fetches all items that are not soft-deleted
  Future<List<Item>> getItems() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'items',
      where: 'is_deleted = 0',
      orderBy: 'name ASC',
    );
    return List.generate(maps.length, (i) => Item.fromMap(maps[i]));
  }

  /// Fetches a specific item by ID
  Future<Item?> getItem(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'items',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Item.fromMap(maps.first);
  }

  /// Inserts a new item, writes to AuditLog and SyncQueue in a txn
  Future<void> insertItem(Item item, String deviceId) async {
    final db = await _dbHelper.database;
    final map = item.toMap();

    await db.transaction((txn) async {
      await txn.insert('items', map);

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'items',
        'record_id': item.id,
        'action': 'CREATE',
        'old_values': null,
        'new_values': jsonEncode(map),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'CREATE',
        'table_name': 'items',
        'record_id': item.id,
        'payload': jsonEncode(map),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Updates an item, writes to AuditLog and SyncQueue in a txn
  Future<void> updateItem(Item item, String deviceId) async {
    final db = await _dbHelper.database;
    final currentItem = await getItem(item.id);
    if (currentItem == null) return;
    final map = item.toMap();

    await db.transaction((txn) async {
      await txn.update(
        'items',
        map,
        where: 'id = ?',
        whereArgs: [item.id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'items',
        'record_id': item.id,
        'action': 'EDIT',
        'old_values': jsonEncode(currentItem.toMap()),
        'new_values': jsonEncode(map),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'EDIT',
        'table_name': 'items',
        'record_id': item.id,
        'payload': jsonEncode(map),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Soft deletes an item (retains in recycle bin for 30 days)
  Future<void> deleteItem(String id, String deviceId) async {
    final db = await _dbHelper.database;
    final currentItem = await getItem(id);
    if (currentItem == null) return;

    final updatedMap = currentItem.copyWith(isDeleted: true).toMap();

    await db.transaction((txn) async {
      await txn.update(
        'items',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'items',
        'record_id': id,
        'action': 'DELETE',
        'old_values': jsonEncode(currentItem.toMap()),
        'new_values': jsonEncode(updatedMap),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'DELETE',
        'table_name': 'items',
        'record_id': id,
        'payload': jsonEncode(updatedMap),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Computes the current stock on hand for a given item
  Future<double> getItemStock(String itemId) async {
    final db = await _dbHelper.database;

    // Sum of purchases (active)
    final List<Map<String, dynamic>> purchaseRes = await db.rawQuery('''
      SELECT COALESCE(SUM(pi.qty), 0.0) as total
      FROM purchase_items pi
      JOIN purchases p ON pi.purchase_id = p.id
      WHERE pi.item_id = ? AND p.is_deleted = 0
    ''', [itemId]);

    // Sum of sales (active)
    final List<Map<String, dynamic>> saleRes = await db.rawQuery('''
      SELECT COALESCE(SUM(si.qty), 0.0) as total
      FROM sale_items si
      JOIN sales s ON si.sale_id = s.id
      WHERE si.item_id = ? AND s.is_deleted = 0
    ''', [itemId]);

    final double totalPurchased = (purchaseRes.first['total'] as num).toDouble();
    final double totalSold = (saleRes.first['total'] as num).toDouble();

    return totalPurchased - totalSold;
  }

  /// Gets the movement history (purchases and sales) for a specific item
  Future<List<StockMovement>> getItemMovementHistory(String itemId) async {
    final db = await _dbHelper.database;

    // Load purchases for the item
    final List<Map<String, dynamic>> purchaseRows = await db.rawQuery('''
      SELECT p.id as txn_id, p.invoice_no, 'PURCHASE' as type, pt.name as party_name, p.date, pi.qty, pi.rate
      FROM purchase_items pi
      JOIN purchases p ON pi.purchase_id = p.id
      JOIN parties pt ON p.party_id = pt.id
      WHERE pi.item_id = ? AND p.is_deleted = 0
    ''', [itemId]);

    // Load sales for the item
    final List<Map<String, dynamic>> saleRows = await db.rawQuery('''
      SELECT s.id as txn_id, s.invoice_no, 'SALE' as type, pt.name as party_name, s.date, si.qty, si.rate
      FROM sale_items si
      JOIN sales s ON si.sale_id = s.id
      JOIN parties pt ON s.party_id = pt.id
      WHERE si.item_id = ? AND s.is_deleted = 0
    ''', [itemId]);

    // Combine and sort chronologically
    final List<Map<String, dynamic>> combined = [...purchaseRows, ...saleRows];
    combined.sort((a, b) {
      final DateTime dateA = DateTime.parse(a['date'] as String);
      final DateTime dateB = DateTime.parse(b['date'] as String);
      return dateA.compareTo(dateB);
    });

    double runningStock = 0.0;
    final List<StockMovement> movements = [];

    for (final row in combined) {
      final String type = row['type'] as String;
      final double qty = (row['qty'] as num).toDouble();
      final double change = type == 'PURCHASE' ? qty : -qty;
      runningStock += change;

      movements.add(StockMovement(
        transactionId: row['txn_id'] as String,
        invoiceNo: row['invoice_no'] as String,
        type: type,
        partyName: row['party_name'] as String,
        date: DateTime.parse(row['date'] as String),
        qty: change,
        rate: (row['rate'] as num).toDouble(),
        runningStock: runningStock,
      ));
    }

    return movements.reversed.toList(); // Newest first for UI display
  }

  /// Evaluates running stock for an item and flags any sale transaction that causes negative stock.
  /// Returns a list of invoice numbers that are invalid (causes stock to go below zero).
  Future<List<String>> checkNegativeStockIssues(String itemId) async {
    final db = await _dbHelper.database;

    final List<Map<String, dynamic>> purchaseRows = await db.rawQuery('''
      SELECT p.invoice_no, 'PURCHASE' as type, p.date, pi.qty
      FROM purchase_items pi
      JOIN purchases p ON pi.purchase_id = p.id
      WHERE pi.item_id = ? AND p.is_deleted = 0
    ''', [itemId]);

    final List<Map<String, dynamic>> saleRows = await db.rawQuery('''
      SELECT s.invoice_no, 'SALE' as type, s.date, si.qty
      FROM sale_items si
      JOIN sales s ON si.sale_id = s.id
      WHERE si.item_id = ? AND s.is_deleted = 0
    ''', [itemId]);

    final List<Map<String, dynamic>> combined = [...purchaseRows, ...saleRows];
    combined.sort((a, b) {
      final DateTime dateA = DateTime.parse(a['date'] as String);
      final DateTime dateB = DateTime.parse(b['date'] as String);
      return dateA.compareTo(dateB);
    });

    double runningStock = 0.0;
    final List<String> invalidInvoiceNos = [];

    for (final row in combined) {
      final String type = row['type'] as String;
      final double qty = (row['qty'] as num).toDouble();
      final String invoiceNo = row['invoice_no'] as String;

      if (type == 'PURCHASE') {
        runningStock += qty;
      } else {
        runningStock -= qty;
        if (runningStock < 0) {
          invalidInvoiceNos.add(invoiceNo);
        }
      }
    }

    return invalidInvoiceNos;
  }

  /// Retrieves list of batches/lots for an item with stock and other details
  Future<List<BatchStockDetails>> getAvailableBatchesForItem(String itemId, {String? excludeSaleId}) async {
    final db = await _dbHelper.database;

    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT 
        pi.lot_no,
        pi.hsn_code,
        pi.mfg_date,
        pi.exp_date,
        pi.manufacturer,
        pi.packing,
        pi.rate as purchase_rate,
        (
          SELECT COALESCE(SUM(p_item.qty), 0.0) 
          FROM purchase_items p_item 
          JOIN purchases p ON p_item.purchase_id = p.id 
          WHERE p_item.item_id = pi.item_id AND p_item.lot_no = pi.lot_no AND p.is_deleted = 0
        ) as total_purchased,
        (
          SELECT COALESCE(SUM(s_item.qty), 0.0) 
          FROM sale_items s_item 
          JOIN sales s ON s_item.sale_id = s.id 
          WHERE s_item.item_id = pi.item_id AND s_item.batch_no = pi.lot_no AND s.is_deleted = 0
          ${excludeSaleId != null ? 'AND s.id != ?' : ''}
        ) as total_sold
      FROM purchase_items pi
      JOIN purchases p ON pi.purchase_id = p.id
      WHERE pi.item_id = ? AND p.is_deleted = 0
      GROUP BY pi.lot_no
    ''', excludeSaleId != null ? [excludeSaleId, itemId] : [itemId]);

    final List<BatchStockDetails> batches = [];
    for (final row in rows) {
      final double totalPurchased = (row['total_purchased'] as num).toDouble();
      final double totalSold = (row['total_sold'] as num).toDouble();
      final double remainingStock = totalPurchased - totalSold;

      batches.add(BatchStockDetails(
        batchNo: row['lot_no'] as String? ?? 'N/A',
        hsnCode: row['hsn_code'] as String? ?? '',
        mfgDate: row['mfg_date'] as String?,
        expDate: row['exp_date'] as String?,
        manufacturer: row['manufacturer'] as String?,
        packing: row['packing'] as String?,
        remainingStock: remainingStock,
        purchaseRate: (row['purchase_rate'] as num).toDouble(),
      ));
    }
    return batches;
  }

  /// Retrieves distinct manufacturer/company names across historic purchase and sale items
  Future<List<String>> getDistinctManufacturers() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> purchaseRows = await db.rawQuery('''
      SELECT DISTINCT manufacturer FROM purchase_items 
      WHERE manufacturer IS NOT NULL AND manufacturer != ''
      ORDER BY manufacturer ASC
    ''');
    final List<Map<String, dynamic>> saleRows = await db.rawQuery('''
      SELECT DISTINCT manufacturer FROM sale_items 
      WHERE manufacturer IS NOT NULL AND manufacturer != ''
      ORDER BY manufacturer ASC
    ''');
    
    final Set<String> manufacturers = {};
    for (final row in purchaseRows) {
      manufacturers.add(row['manufacturer'] as String);
    }
    for (final row in saleRows) {
      manufacturers.add(row['manufacturer'] as String);
    }
    
    return manufacturers.toList()..sort();
  }
}

class BatchStockDetails {
  final String batchNo;
  final String hsnCode;
  final String? mfgDate;
  final String? expDate;
  final String? manufacturer;
  final String? packing;
  final double remainingStock;
  final double purchaseRate;

  BatchStockDetails({
    required this.batchNo,
    required this.hsnCode,
    this.mfgDate,
    this.expDate,
    this.manufacturer,
    this.packing,
    required this.remainingStock,
    required this.purchaseRate,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchStockDetails &&
          runtimeType == other.runtimeType &&
          batchNo == other.batchNo;

  @override
  int get hashCode => batchNo.hashCode;
}
