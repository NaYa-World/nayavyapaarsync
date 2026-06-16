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

    test('v8 to v9 migration preserves existing payments and configures new check constraints/indexes', () async {
      // 1. Create a version 8 database with the v8 schema
      final dbV8 = await openDatabase(
        dbPath,
        version: 8,
        onCreate: (db, version) async {
          // Create parties table so foreign keys work
          await db.execute('''
            CREATE TABLE parties (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              phone TEXT NOT NULL,
              address TEXT NOT NULL,
              created_at TEXT NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');

          // Create purchases table so indexes can be tested
          await db.execute('CREATE TABLE purchases (id TEXT PRIMARY KEY, party_id TEXT)');
          // Create sales table so indexes can be tested
          await db.execute('CREATE TABLE sales (id TEXT PRIMARY KEY, party_id TEXT)');

          // Version 8 payments schema
          await db.execute('''
            CREATE TABLE payments (
              id TEXT PRIMARY KEY,
              party_id TEXT NOT NULL,
              direction TEXT NOT NULL,
              amount REAL NOT NULL,
              mode TEXT NOT NULL,
              date TEXT NOT NULL,
              reference_no TEXT,
              linked_invoice_id TEXT,
              notes TEXT,
              created_at TEXT NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0,
              cheque_no TEXT,
              cheque_bank TEXT,
              cheque_date TEXT,
              cheque_status TEXT CHECK(cheque_status IN ('ISSUED','CLEARED','BOUNCED','CANCELLED')),
              FOREIGN KEY(party_id) REFERENCES parties(id)
            )
          ''');
        },
      );

      // Insert a dummy party
      await dbV8.insert('parties', {
        'id': 'party-x',
        'name': 'Test Party',
        'type': 'CUSTOMER',
        'phone': '1234567890',
        'address': 'Test',
        'created_at': '2026-06-15T12:00:00Z',
      });

      // Insert a payment with standard ISSUED cheque status
      await dbV8.insert('payments', {
        'id': 'pay-v8-1',
        'party_id': 'party-x',
        'direction': 'RECEIVED',
        'amount': 1000.0,
        'mode': 'CHEQUE',
        'date': '2026-06-15T12:00:00Z',
        'created_at': '2026-06-15T12:00:00Z',
        'cheque_no': 'CHQ-12345',
        'cheque_bank': 'SBI',
        'cheque_date': '2026-06-15',
        'cheque_status': 'ISSUED',
      });

      await dbV8.close();

      // 2. Open using DbHelper (triggers v9 migration)
      final database = await dbHelper.database;

      // 3. Verify existing payment details are preserved
      final paymentRows = await database.query('payments');
      expect(paymentRows.length, 1);
      expect(paymentRows.first['id'], 'pay-v8-1');
      expect(paymentRows.first['cheque_status'], 'ISSUED');

      // 4. Try inserting a payment with 'RECEIVED' and 'PENDING' status (new in v9)
      await database.insert('payments', {
        'id': 'pay-v9-recv',
        'party_id': 'party-x',
        'direction': 'RECEIVED',
        'amount': 2000.0,
        'mode': 'CHEQUE',
        'date': '2026-06-15T12:00:00Z',
        'created_at': '2026-06-15T12:00:00Z',
        'cheque_no': 'CHQ-54321',
        'cheque_bank': 'HDFC',
        'cheque_date': '2026-06-15',
        'cheque_status': 'RECEIVED',
      });

      await database.insert('payments', {
        'id': 'pay-v9-pend',
        'party_id': 'party-x',
        'direction': 'RECEIVED',
        'amount': 3000.0,
        'mode': 'CHEQUE',
        'date': '2026-06-15T12:00:00Z',
        'created_at': '2026-06-15T12:00:00Z',
        'cheque_no': 'CHQ-67890',
        'cheque_bank': 'ICICI',
        'cheque_date': '2026-06-15',
        'cheque_status': 'PENDING',
      });

      final verifyStatus = await database.query('payments', where: "id IN ('pay-v9-recv', 'pay-v9-pend')");
      expect(verifyStatus.length, 2);

      // 5. Verify indexes are present in the upgraded database
      final indexes = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'"
      );
      final indexNames = indexes.map((row) => row['name'] as String).toList();
      expect(indexNames, contains('idx_payments_party_id'));
      expect(indexNames, contains('idx_purchases_party_id'));
      expect(indexNames, contains('idx_sales_party_id'));
    });

    test('v9 to v10 migration creates double-entry tables, indexes, and virtual tables', () async {
      // 1. Create a version 9 database with standard v9 schema
      final dbV9 = await openDatabase(
        dbPath,
        version: 9,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE payments (id TEXT PRIMARY KEY)');
        },
      );
      await dbV9.close();

      // 2. Open using DbHelper (triggers v10 migration)
      final database = await dbHelper.database;

      // 3. Verify all Version 10 tables exist
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
      );
      final tableNames = tables.map((row) => row['name'] as String).toList();

      expect(tableNames, contains('ledger_groups'));
      expect(tableNames, contains('ledgers'));
      expect(tableNames, contains('vouchers'));
      expect(tableNames, contains('voucher_lines'));
      expect(tableNames, contains('bill_allocations'));
      expect(tableNames, contains('godowns'));
      expect(tableNames, contains('batches'));
      expect(tableNames, contains('stock_movements'));
      expect(tableNames, contains('bank_instruments'));
      expect(tableNames, contains('bank_reconciliation'));

      // 4. Verify Virtual Tables (FTS5) exist
      expect(tableNames, contains('fts_vouchers'));
      expect(tableNames, contains('fts_ledgers'));

      // 5. Verify indexes exist
      final indexes = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'"
      );
      final indexNames = indexes.map((row) => row['name'] as String).toList();
      expect(indexNames, contains('idx_vouchers_company_date'));
      expect(indexNames, contains('idx_voucher_lines_voucher'));
      expect(indexNames, contains('idx_stock_movements_item'));
    });

    test('v11 to v12 migration adds stock_group column to items table', () async {
      // 1. Create a version 11 database
      final dbV11 = await openDatabase(
        dbPath,
        version: 11,
        onCreate: (db, version) async {
          // Version 11 items schema (without stock_group)
          await db.execute('''
            CREATE TABLE items (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              category TEXT CHECK(category IN ('SEED', 'FERTILISER')) NOT NULL,
              hsn_code TEXT NOT NULL,
              gst_rate REAL NOT NULL,
              primary_unit TEXT CHECK(primary_unit IN ('BAG', 'BOX')) NOT NULL,
              bag_weight_kg REAL,
              box_weight_kg REAL,
              low_stock_threshold REAL NOT NULL DEFAULT 10.0,
              created_at TEXT NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      );

      // Insert an item in v11 items
      await dbV11.insert('items', {
        'id': 'item-v11-1',
        'name': 'Paddy Seed',
        'category': 'SEED',
        'hsn_code': '12099190',
        'gst_rate': 5.0,
        'primary_unit': 'BAG',
        'bag_weight_kg': 25.0,
        'low_stock_threshold': 10.0,
        'created_at': '2026-06-15T12:00:00Z',
        'is_deleted': 0,
      });

      await dbV11.close();

      // 2. Open using DbHelper (triggers v12 migration)
      final database = await dbHelper.database;

      // 3. Verify stock_group exists and defaults to 'General'
      final items = await database.query('items');
      expect(items.length, 1);
      expect(items.first['stock_group'], 'General');
    });
  });
}
