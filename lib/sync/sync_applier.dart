import 'dart:convert';
import 'package:sqflite/sqflite.dart';

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
      await logConflict(db, tableName, recordId, operation, localPayload, remotePayload);
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
    String operation,
    Map<String, dynamic>? localPayload,
    Map<String, dynamic> remotePayload,
  ) async {
    final conflictId = '${DateTime.now().millisecondsSinceEpoch}_$recordId';
    await db.insert('sync_conflicts', {
      'id': conflictId,
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation,
      'local_payload': localPayload != null ? jsonEncode(localPayload) : null,
      'remote_payload': jsonEncode(remotePayload),
      'resolved': 0,
      'created_at': DateTime.now().toIso8601String(),
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
    } else if (tableName == 'sales') {
      final saleMap = payload['sale'] as Map<String, dynamic>;
      final items = payload['items'] as List<dynamic>? ?? [];

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
}
