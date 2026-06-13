import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/settings.dart';
import '../database/db_helper.dart';

class SettingsRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Fetches the application settings
  Future<Settings> getSettings() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('settings');
    return Settings.fromMapList(maps);
  }

  /// Saves settings. Adds to AuditLog and SyncQueue in a transaction.
  Future<void> saveSettings(Settings settings, String deviceId) async {
    final db = await _dbHelper.database;
    final currentSettings = await getSettings();
    final newMap = settings.toMap();

    await db.transaction((txn) async {
      for (final entry in newMap.entries) {
        await txn.insert(
          'settings',
          {
            'key': entry.key,
            'value': entry.value,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 1. Audit Log record
      final String auditId = _uuid.v4();
      await txn.insert('audit_logs', {
        'id': auditId,
        'table_name': 'settings',
        'record_id': 'app_settings',
        'action': 'EDIT',
        'old_values': currentSettings.isValid ? jsonEncode(currentSettings.toMap()) : null,
        'new_values': jsonEncode(newMap),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // 2. Sync Queue record
      final String syncId = _uuid.v4();
      await txn.insert('sync_queue', {
        'id': syncId,
        'operation': 'EDIT',
        'table_name': 'settings',
        'record_id': 'app_settings',
        'payload': jsonEncode(newMap),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }
}
