import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class SyncApplier {
  /// Applies a single remote change log record to the local SQLite database.
  /// If a conflict is detected (the record has a local pending edit in sync_queue),
  /// it halts applying the change for this record, constructs a conflict entry,
  /// and writes it to the `sync_conflicts` table for manual resolution.
  static Future<bool> applyRemoteChange(
    Database db,
    String operation,
    String tableName,
    String recordId,
    Map<String, dynamic> remotePayload,
  ) async {
    // 1. Check if the local record has unsynced pending changes
    final isConflicted = await isRecordPendingLocally(db, tableName, recordId);
    if (isConflicted) {
      // Fetch local representation of the record
      final localPayload = await getLocalPayload(db, tableName, recordId);
      
      // Log conflict
      await logConflict(
        db,
        tableName,
        recordId,
        '_full_row',
        jsonEncode(localPayload ?? {}),
        'local',
        jsonEncode(remotePayload),
        'remote',
      );
      return false; // Did not apply remote change due to conflict
    }

    // 2. No conflict, safe to apply
    await applySyncItem(db, operation, tableName, recordId, remotePayload);
    return true; // Successfully applied remote change
  }

  /// Checks if a record has any pending local changes in the sync queue.
  static Future<bool> isRecordPendingLocally(
    Database db,
    String tableName,
    String recordId,
  ) async {
    final List<Map<String, dynamic>> res = await db.query(
      'sync_queue',
      where: "table_name = ? AND record_id = ? AND status = 'PENDING'",
      whereArgs: [tableName, recordId],
    );
    return res.isNotEmpty;
  }

  /// Logs a conflict to the sync_conflicts table.
  static Future<void> logConflict(
  Database db,
  String tableName,
  String recordId,
  String fieldName,        // pass '_full_row' for now
  String localValue,       // JSON string of local record
  String localDevice,
  String remoteValue,      // JSON string of remote record  
  String remoteDevice,
) async {
  final conflictId = const Uuid().v4();
  final now = DateTime.now().toIso8601String();
  await db.insert('sync_conflicts', {
    'id': conflictId,
    'table_name': tableName,
    'record_id': recordId,
    'field_name': fieldName,
    'local_value': localValue,
    'local_device': localDevice,
    'local_timestamp': now,
    'remote_value': remoteValue,
    'remote_device': remoteDevice,
    'remote_timestamp': now,
    'status': 'pending',
    'created_at': now,
  });
}

  /// Low-level database applying helper.
  static Future<void> applySyncItem(
    Database db,
    String operation,
    String tableName,
    String recordId,
    Map<String, dynamic> payload,
  ) async {
    if (tableName == 'purchases') {
      final purchaseMap = payload['purchase'] as Map<String, dynamic>;
      final items = payload['items'] as List<dynamic>? ?? [];

      final Set<String> affectedItems = {};
      final List<Map<String, dynamic>> oldItems = await db.query(
        'purchase_items',
        columns: ['item_id'],
        where: 'purchase_id = ?',
        whereArgs: [recordId],
      );
      for (final row in oldItems) {
        affectedItems.add(row['item_id'] as String);
      }
      for (final item in items) {
        affectedItems.add((item as Map)['item_id'] as String);
      }

      // Delete old line items
      await db.delete(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [recordId],
      );

      // Insert/replace purchase parent row
      await db.insert(
        'purchases',
        purchaseMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Insert new child items
      for (final item in items) {
        await db.insert(
          'purchase_items',
          Map<String, dynamic>.from(item as Map),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Recalculate stock balances
      for (final itemId in affectedItems) {
        await _updateStockBalance(db, itemId);
      }
    } else if (tableName == 'sales') {
      final saleMap = payload['sale'] as Map<String, dynamic>;
      final items = payload['items'] as List<dynamic>? ?? [];

      final Set<String> affectedItems = {};
      final List<Map<String, dynamic>> oldItems = await db.query(
        'sale_items',
        columns: ['item_id'],
        where: 'sale_id = ?',
        whereArgs: [recordId],
      );
      for (final row in oldItems) {
        affectedItems.add(row['item_id'] as String);
      }
      for (final item in items) {
        affectedItems.add((item as Map)['item_id'] as String);
      }

      // Delete old line items
      await db.delete(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [recordId],
      );

      // Insert/replace sale parent row
      await db.insert(
        'sales',
        saleMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Insert new child items
      for (final item in items) {
        await db.insert(
          'sale_items',
          Map<String, dynamic>.from(item as Map),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Recalculate stock balances
      for (final itemId in affectedItems) {
        await _updateStockBalance(db, itemId);
      }
    } else if (tableName == 'settings') {
      for (final entry in payload.entries) {
        await db.insert(
          'settings',
          {
            'key': entry.key,
            'value': entry.value.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } else if (tableName == 'vouchers') {
      final voucherMap = payload['voucher'] as Map<String, dynamic>;
      final lines = payload['voucher_lines'] as List<dynamic>? ?? [];
      final billAllocations = payload['bill_allocations'] as List<dynamic>? ?? [];
      final stockMovements = payload['stock_movements'] as List<dynamic>? ?? [];
      final bankInstruments = payload['bank_instruments'] as List<dynamic>? ?? [];

      // Cascade delete local dependent rows to prevent orphan/integrity issues
      await db.delete('voucher_lines', where: 'voucher_id = ?', whereArgs: [recordId]);
      await db.delete(
        'bill_allocations',
        where: 'voucher_line_id IN (SELECT id FROM voucher_lines WHERE voucher_id = ?)',
        whereArgs: [recordId],
      );
      await db.delete('stock_movements', where: 'ref_voucher_id = ?', whereArgs: [recordId]);
      await db.delete('bank_instruments', where: 'voucher_id = ?', whereArgs: [recordId]);

      // Insert parent
      await db.insert('vouchers', voucherMap, conflictAlgorithm: ConflictAlgorithm.replace);

      // Re-insert child rows
      for (final line in lines) {
        await db.insert('voucher_lines', Map<String, dynamic>.from(line as Map), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final ba in billAllocations) {
        await db.insert('bill_allocations', Map<String, dynamic>.from(ba as Map), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final sm in stockMovements) {
        await db.insert('stock_movements', Map<String, dynamic>.from(sm as Map), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final bi in bankInstruments) {
        await db.insert('bank_instruments', Map<String, dynamic>.from(bi as Map), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } else {
      // items, parties, expenses, payments
      await db.insert(
        tableName,
        payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Retrieves the current local payload for a record.
  static Future<Map<String, dynamic>?> getLocalPayload(
    Database db,
    String tableName,
    String recordId,
  ) async {
    if (tableName == 'purchases') {
      final List<Map<String, dynamic>> purchaseMaps = await db.query(
        'purchases',
        where: 'id = ?',
        whereArgs: [recordId],
      );
      if (purchaseMaps.isEmpty) return null;

      final List<Map<String, dynamic>> itemMaps = await db.query(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [recordId],
      );

      return {
        'purchase': purchaseMaps.first,
        'items': itemMaps,
      };
    } else if (tableName == 'sales') {
      final List<Map<String, dynamic>> saleMaps = await db.query(
        'sales',
        where: 'id = ?',
        whereArgs: [recordId],
      );
      if (saleMaps.isEmpty) return null;

      final List<Map<String, dynamic>> itemMaps = await db.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [recordId],
      );

      return {
        'sale': saleMaps.first,
        'items': itemMaps,
      };
    } else if (tableName == 'settings') {
      final List<Map<String, dynamic>> maps = await db.query('settings');
      final Map<String, dynamic> result = {};
      for (final row in maps) {
        result[row['key'] as String] = row['value'];
      }
      return result;
    } else if (tableName == 'vouchers') {
      final List<Map<String, dynamic>> voucherMaps = await db.query(
        'vouchers',
        where: 'id = ?',
        whereArgs: [recordId],
      );
      if (voucherMaps.isEmpty) return null;

      final List<Map<String, dynamic>> lines = await db.query(
        'voucher_lines',
        where: 'voucher_id = ?',
        whereArgs: [recordId],
      );
      final List<String> lineIds = lines.map((l) => l['id'] as String).toList();
      
      final List<Map<String, dynamic>> billAllocations = lineIds.isEmpty
          ? []
          : await db.query(
              'bill_allocations',
              where: 'voucher_line_id IN (${lineIds.map((_) => '?').join(',')})',
              whereArgs: lineIds,
            );
      
      final List<Map<String, dynamic>> stockMovements = await db.query(
        'stock_movements',
        where: 'ref_voucher_id = ?',
        whereArgs: [recordId],
      );
      
      final List<Map<String, dynamic>> bankInstruments = await db.query(
        'bank_instruments',
        where: 'voucher_id = ?',
        whereArgs: [recordId],
      );

      return {
        'voucher': voucherMaps.first,
        'voucher_lines': lines,
        'bill_allocations': billAllocations,
        'stock_movements': stockMovements,
        'bank_instruments': bankInstruments,
      };
    } else {
      final List<Map<String, dynamic>> maps = await db.query(
        tableName,
        where: 'id = ?',
        whereArgs: [recordId],
      );
      if (maps.isEmpty) return null;
      return maps.first;
    }
  }

  static Future<void> _updateStockBalance(Database db, String itemId) async {
    final List<Map<String, dynamic>> purchaseRes = await db.rawQuery('''
      SELECT COALESCE(SUM(pi.qty), 0.0) as total
      FROM purchase_items pi
      JOIN purchases p ON pi.purchase_id = p.id
      WHERE pi.item_id = ? AND p.is_deleted = 0
    ''', [itemId]);

    final List<Map<String, dynamic>> saleRes = await db.rawQuery('''
      SELECT COALESCE(SUM(si.qty), 0.0) as total
      FROM sale_items si
      JOIN sales s ON si.sale_id = s.id
      WHERE si.item_id = ? AND s.is_deleted = 0
    ''', [itemId]);

    final double totalPurchased = (purchaseRes.first['total'] as num).toDouble();
    final double totalSold = (saleRes.first['total'] as num).toDouble();
    final double stock = totalPurchased - totalSold;

    await db.insert(
      'stock_balances',
      {
        'item_id': itemId,
        'qty': stock,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
