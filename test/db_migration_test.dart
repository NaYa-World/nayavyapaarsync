import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:godown_management/data/database/db_helper.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database Migration Tests', () {
    late DbHelper dbHelper;
    late String dbPath;

    setUp(() async {
      dbHelper = DbHelper();
      await dbHelper.close();
      final databasePath = await getDatabasesPath();
      dbPath = '$databasePath/godown_management.db';
      try {
        await deleteDatabase(dbPath);
      } catch (_) {}
    });

    tearDown(() async {
      await dbHelper.close();
      try {
        await deleteDatabase(dbPath);
      } catch (_) {}
    });

    test('v5 to v7 migration preserves existing sync_queue rows and configures defaults', () async {
      // 1. Create a version 5 database with the legacy schema
      final dbV5 = await openDatabase(
        dbPath,
        version: 5,
        onCreate: (db, version) async {
          // Version 5 sync_queue
          await db.execute('''
            CREATE TABLE sync_queue (
              id TEXT PRIMARY KEY,
              operation TEXT NOT NULL,
              table_name TEXT NOT NULL,
              record_id TEXT NOT NULL,
              payload TEXT,
              created_at TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'PENDING'
            )
          ''');

          // Version 5 sync_conflicts
          await db.execute('''
            CREATE TABLE sync_conflicts (
              id TEXT PRIMARY KEY,
              table_name TEXT NOT NULL,
              record_id TEXT NOT NULL,
              operation TEXT NOT NULL,
              local_payload TEXT,
              remote_payload TEXT,
              resolved INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
        },
      );

      // Insert a dummy record in v5 sync_queue
      await dbV5.insert('sync_queue', {
        'id': 'sq-1',
        'operation': 'EDIT',
        'table_name': 'items',
        'record_id': 'item-123',
        'payload': '{"name":"Old Item","rate":100}',
        'created_at': '2026-06-14T12:00:00Z',
        'status': 'PENDING',
      });

      // Insert a dummy record in v5 sync_conflicts
      await dbV5.insert('sync_conflicts', {
        'id': 'sc-1',
        'table_name': 'items',
        'record_id': 'item-123',
        'operation': 'EDIT',
        'local_payload': '{"rate":120}',
        'remote_payload': '{"rate":130}',
        'resolved': 0,
        'created_at': '2026-06-14T12:05:00Z',
      });

      await dbV5.close();

      // 2. Open the database using DbHelper (triggering v7 migration)
      final database = await dbHelper.database;

      // 3. Verify sync_queue data and columns
      final queueRows = await database.query('sync_queue');
      expect(queueRows.length, 1);
      final migratedQueue = queueRows.first;

      expect(migratedQueue['id'], 'sq-1');
      expect(migratedQueue['operation'], 'EDIT');
      expect(migratedQueue['table_name'], 'items');
      expect(migratedQueue['record_id'], 'item-123');
      expect(migratedQueue['payload'], '{"name":"Old Item","rate":100}');
      expect(migratedQueue['created_at'], '2026-06-14T12:00:00Z');
      expect(migratedQueue['status'], 'PENDING');
      
      // Verify new columns acquired default values
      expect(migratedQueue['field_name'], '_full_row');
      expect(migratedQueue['old_value'], isNull);
      expect(migratedQueue['new_value'], isNull);
      expect(migratedQueue['device_role'], 'owner');
      expect(migratedQueue['is_resolution'], 0);

      // 4. Verify sync_conflicts was dropped and recreated with new schema
      // Since it was dropped, the old v5 conflict row should be gone
      final conflictRows = await database.query('sync_conflicts');
      expect(conflictRows, isEmpty);

      // Insert into new sync_conflicts to check schema
      await database.insert('sync_conflicts', {
        'id': 'new-sc-1',
        'table_name': 'items',
        'record_id': 'item-123',
        'field_name': 'rate',
        'local_value': '120',
        'local_device': 'device1',
        'local_timestamp': '2026-06-14T12:05:00Z',
        'remote_value': '130',
        'remote_device': 'device2',
        'remote_timestamp': '2026-06-14T12:06:00Z',
        'status': 'pending',
        'created_at': '2026-06-14T12:05:00Z',
      });

      final verifyConflicts = await database.query('sync_conflicts');
      expect(verifyConflicts.length, 1);
      expect(verifyConflicts.first['field_name'], 'rate');

      // 5. Verify conflict_audit_log table exists and is writable
      await database.insert('conflict_audit_log', {
        'id': 'audit-1',
        'conflict_id': 'new-sc-1',
        'table_name': 'items',
        'record_id': 'item-123',
        'field_name': 'rate',
        'winning_value': '130',
        'losing_value': '120',
        'resolved_by': 'owner',
        'resolved_at': '2026-06-14T12:10:00Z',
        'resolution_source': 'local',
      });

      final verifyAudit = await database.query('conflict_audit_log');
      expect(verifyAudit.length, 1);
      expect(verifyAudit.first['resolution_source'], 'local');
    });

    test('Fresh install at v7 initializes correct tables', () async {
      // 1. Let DbHelper create database from scratch (v7)
      final database = await dbHelper.database;

      // 2. Verify all required tables exist
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
      );
      final tableNames = tables.map((row) => row['name'] as String).toList();

      expect(tableNames, contains('sync_queue'));
      expect(tableNames, contains('sync_conflicts'));
      expect(tableNames, contains('conflict_audit_log'));
      expect(tableNames, contains('items'));
      expect(tableNames, contains('parties'));

      // 3. Verify sync_queue columns on fresh install
      final queueColumns = await database.rawQuery("PRAGMA table_info(sync_queue)");
      final queueColNames = queueColumns.map((col) => col['name'] as String).toList();
      expect(queueColNames, containsAll(['field_name', 'old_value', 'new_value', 'device_role', 'is_resolution']));

      // 4. Verify sync_conflicts columns on fresh install
      final conflictColumns = await database.rawQuery("PRAGMA table_info(sync_conflicts)");
      final conflictColNames = conflictColumns.map((col) => col['name'] as String).toList();
      expect(conflictColNames, containsAll(['field_name', 'local_value', 'remote_value', 'status', 'resolved_by']));
    });
  });
}
