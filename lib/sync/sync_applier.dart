import 'dart:convert';
import 'package:sqflite/sqflite.dart';

class SyncApplier {
  /// Applies a single remote change log record to the local SQLite database.
  /// If a conflict is detected (the record has a local pending edit in sync_queue),
  /// it halts applying the change for this record, constructs a conflict entry,
  /// and writes it to the `sync_conflicts` table for manual resolution.
  static Future<bool> applyRemoteChange(
    DatabaseExecutor db,
    Map<String, dynamic> remoteEntry,
  ) async {
    final operation = remoteEntry['operation'] as String;
    final tableName = remoteEntry['table_name'] as String;
    final recordId = remoteEntry['record_id'] as String;
    final fieldName = remoteEntry['field_name'] as String? ?? '_full_row';
    final isResolution = (remoteEntry['is_resolution'] as int? ?? 0) == 1;
    final deviceRole = remoteEntry['device_role'] as String? ?? 'owner';
    final newValue = remoteEntry['new_value'] as String?;
    final remoteTimestamp = remoteEntry['created_at'] as String;

    // Resolution entries — apply unconditionally, SUPERSEDE local pending
    if (isResolution) {
      await db.update(
        'sync_queue',
        {'status': 'SUPERSEDED'},
        where: "table_name = ? AND record_id = ? AND field_name = ? AND status = 'PENDING'",
        whereArgs: [tableName, recordId, fieldName],
      );
      if (newValue != null) {
        await db.update(
          tableName,
          {fieldName: newValue},
          where: 'id = ?',
          whereArgs: [recordId],
        );
      }
      return true;
    }

    // Legacy whole-row entries — apply directly, no conflict check
    if (fieldName == '_full_row') {
      final payload = remoteEntry['payload'] != null
          ? jsonDecode(remoteEntry['payload'] as String) as Map<String, dynamic>
          : <String, dynamic>{};
      await applySyncItem(db, operation, tableName, recordId, payload);
      return true;
    }

    // CREATE / DELETE — apply directly
    if (operation == 'CREATE' || operation == 'DELETE') {
      final payload = remoteEntry['payload'] != null
          ? jsonDecode(remoteEntry['payload'] as String) as Map<String, dynamic>
          : <String, dynamic>{};
      await applySyncItem(db, operation, tableName, recordId, payload);
      return true;
    }

    // EDIT — field-level conflict check
    final localConflict = await db.query(
      'sync_queue',
      where: "table_name = ? AND record_id = ? AND field_name = ? AND status = 'PENDING' AND device_role != ?",
      whereArgs: [tableName, recordId, fieldName, deviceRole],
    );

    if (localConflict.isNotEmpty) {
      // Conflict — log and halt
      await db.insert('sync_conflicts', {
        'id': '${DateTime.now().millisecondsSinceEpoch}_${recordId}_$fieldName',
        'table_name': tableName,
        'record_id': recordId,
        'field_name': fieldName,
        'local_value': localConflict.first['new_value'],
        'local_device': localConflict.first['device_role'],
        'local_timestamp': localConflict.first['created_at'],
        'remote_value': newValue,
        'remote_device': deviceRole,
        'remote_timestamp': remoteTimestamp,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
      return false;
    }

    // No conflict — apply field directly
    if (newValue != null) {
      await db.update(
        tableName,
        {fieldName: newValue},
        where: 'id = ?',
        whereArgs: [recordId],
      );
    }
    return true;
  }

  /// Low-level database applying helper.
  static Future<void> applySyncItem(
    DatabaseExecutor db,
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
    DatabaseExecutor db,
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
