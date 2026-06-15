import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  static Database? _database;

  factory DbHelper() {
    return _instance;
  }

  DbHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String path = join(await getDatabasesPath(), 'godown_management.db');
    return await openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // Enable foreign keys
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE purchase_items ADD COLUMN lot_no TEXT');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN hsn_code TEXT');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN no_of_pkts REAL');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN no_of_bags REAL');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN per_unit TEXT');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN discount_pct REAL');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN mfg_date TEXT');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN exp_date TEXT');
    }
    if (oldVersion < 3) {
      // Alter purchases table
      await db.execute('ALTER TABLE purchases ADD COLUMN category TEXT');
      await db.execute("UPDATE purchases SET category = 'SEED' WHERE category IS NULL");
      
      // Alter sales table
      await db.execute('ALTER TABLE sales ADD COLUMN category TEXT');
      await db.execute("UPDATE sales SET category = 'SEED' WHERE category IS NULL");
      
      // Alter purchase_items table
      await db.execute('ALTER TABLE purchase_items ADD COLUMN manufacturer TEXT');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN packing TEXT');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN unit_per_case REAL');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN no_of_cases REAL');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN total_units REAL');
      await db.execute('ALTER TABLE purchase_items ADD COLUMN unit_price REAL');
      
      // Alter sale_items table
      await db.execute('ALTER TABLE sale_items ADD COLUMN manufacturer TEXT');
      await db.execute('ALTER TABLE sale_items ADD COLUMN packing TEXT');
      await db.execute('ALTER TABLE sale_items ADD COLUMN batch_no TEXT');
      await db.execute('ALTER TABLE sale_items ADD COLUMN hsn_code TEXT');
      await db.execute('ALTER TABLE sale_items ADD COLUMN mfg_date TEXT');
      await db.execute('ALTER TABLE sale_items ADD COLUMN exp_date TEXT');
      await db.execute('ALTER TABLE sale_items ADD COLUMN unit_per_case REAL');
      await db.execute('ALTER TABLE sale_items ADD COLUMN no_of_cases REAL');
      await db.execute('ALTER TABLE sale_items ADD COLUMN total_units REAL');
      await db.execute('ALTER TABLE sale_items ADD COLUMN unit_price REAL');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE expenses (
          id TEXT PRIMARY KEY,
          category TEXT CHECK(category IN ('RENT', 'ELECTRICITY', 'SALARY', 'HAMALI', 'MAINTENANCE', 'FUEL', 'OTHER')) NOT NULL,
          amount REAL NOT NULL,
          date TEXT NOT NULL,
          description TEXT NOT NULL,
          payment_method TEXT CHECK(payment_method IN ('CASH', 'BANK')) NOT NULL DEFAULT 'CASH',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 5) {
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
    }
    if (oldVersion < 6) {
      // Guard: create sync_queue if upgrading from before it existed
      // Check if table exists first — do not assume _onCreate ran it
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_queue'"
      );
      
      if (tables.isEmpty) {
        // Device upgraded from a version before sync_queue existed
        await db.execute('''
          CREATE TABLE sync_queue (
            id TEXT PRIMARY KEY,
            operation TEXT CHECK(operation IN ('CREATE','EDIT','DELETE')) NOT NULL,
            table_name TEXT NOT NULL,
            record_id TEXT NOT NULL,
            payload TEXT,
            created_at TEXT NOT NULL,
            status TEXT CHECK(status IN ('PENDING','DONE','FAILED','SUPERSEDED')) NOT NULL
          )
        ''');
      } else {
        // Table exists — just add new columns
        // SQLite ALTER ADD COLUMN cannot add NOT NULL without DEFAULT
        // All defaults below are intentional
        await db.execute(
          "ALTER TABLE sync_queue ADD COLUMN field_name TEXT DEFAULT '_full_row'"
        );
        await db.execute(
          "ALTER TABLE sync_queue ADD COLUMN old_value TEXT DEFAULT NULL"
        );
        await db.execute(
          "ALTER TABLE sync_queue ADD COLUMN new_value TEXT DEFAULT NULL"
        );
        await db.execute(
          "ALTER TABLE sync_queue ADD COLUMN device_role TEXT DEFAULT 'owner'"
        );
        await db.execute(
          "ALTER TABLE sync_queue ADD COLUMN is_resolution INTEGER DEFAULT 0"
        );
        // Cannot ALTER CHECK constraint in SQLite
        // SUPERSEDED handled in query logic, not enforced at DB level
      }
    }

    if (oldVersion < 7) {
      // Drop old whole-row conflict table — data is not migrated
      // Old conflicts are unresolvable with new field-level schema
      // Log this drop so users know pending conflicts were cleared
      await db.execute('DROP TABLE IF EXISTS sync_conflicts');
      
      await db.execute('''
        CREATE TABLE sync_conflicts (
          id TEXT PRIMARY KEY,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          field_name TEXT NOT NULL,
          local_value TEXT NOT NULL,
          local_device TEXT NOT NULL,
          local_timestamp TEXT NOT NULL,
          remote_value TEXT NOT NULL,
          remote_device TEXT NOT NULL,
          remote_timestamp TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending', 'resolved', 'superseded')),
          resolved_value TEXT,
          resolved_by TEXT,
          resolved_at TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE conflict_audit_log (
          id TEXT PRIMARY KEY,
          conflict_id TEXT NOT NULL,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          field_name TEXT NOT NULL,
          winning_value TEXT,
          losing_value TEXT,
          resolved_by TEXT NOT NULL,
          resolved_at TEXT NOT NULL,
          resolution_source TEXT NOT NULL
            CHECK(resolution_source IN ('local', 'remote_sync'))
        )
      ''');
    }

    if (oldVersion < 8) {
      // ── 1. Companies table ──────────────────────────────────────────────
      await db.execute('''
        CREATE TABLE IF NOT EXISTS companies (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          gstin TEXT,
          address TEXT,
          phone TEXT,
          state TEXT NOT NULL DEFAULT 'Telangana',
          state_code TEXT NOT NULL DEFAULT '36',
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');

      // Seed first company from existing settings
      final settingsExist = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='settings'"
      )).isNotEmpty;

      String firmName = 'My Company';
      String? gstin;
      String? address;
      String? phone;
      String state = 'Telangana';
      String stateCode = '36';

      if (settingsExist) {
        final settingsRows = await db.query('settings');
        for (final row in settingsRows) {
          final k = row['key'] as String;
          final v = row['value'] as String;
          if (k == 'firm_name' && v.trim().isNotEmpty) firmName = v.trim();
          if (k == 'gstin' && v.trim().isNotEmpty) gstin = v.trim();
          if (k == 'address' && v.trim().isNotEmpty) address = v.trim();
          if (k == 'phone' && v.trim().isNotEmpty) phone = v.trim();
          if (k == 'state' && v.trim().isNotEmpty) state = v.trim();
          if (k == 'state_code' && v.trim().isNotEmpty) stateCode = v.trim();
        }
      }
      final existingCompanies = await db.query('companies', limit: 1);
      if (existingCompanies.isEmpty) {
        await db.insert('companies', {
          'id': 'company_default',
          'name': firmName,
          'gstin': gstin,
          'address': address,
          'phone': phone,
          'state': state,
          'state_code': stateCode,
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // ── 2. Financial Years table ────────────────────────────────────────
      await db.execute('''
        CREATE TABLE IF NOT EXISTS financial_years (
          id TEXT PRIMARY KEY,
          company_id TEXT NOT NULL,
          label TEXT NOT NULL,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          is_locked INTEGER NOT NULL DEFAULT 0,
          locked_by TEXT,
          locked_at TEXT,
          FOREIGN KEY(company_id) REFERENCES companies(id)
        )
      ''');

      // Seed current financial year for the default company
      final now = DateTime.now();
      final fyStart = now.month >= 4
          ? DateTime(now.year, 4, 1)
          : DateTime(now.year - 1, 4, 1);
      final fyEnd = DateTime(fyStart.year + 1, 3, 31);
      final fyLabel =
          'FY ${fyStart.year.toString().substring(2)}-${fyEnd.year.toString().substring(2)}';
      final existingFYs = await db.query('financial_years', limit: 1);
      if (existingFYs.isEmpty) {
        await db.insert('financial_years', {
          'id': 'fy_default',
          'company_id': 'company_default',
          'label': fyLabel,
          'start_date': '${fyStart.year}-04-01',
          'end_date': '${fyEnd.year}-03-31',
          'is_locked': 0,
          'locked_by': null,
          'locked_at': null,
        });
      }

      // ── 3. App Users table ──────────────────────────────────────────────
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_users (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          pin_hash TEXT NOT NULL,
          role TEXT NOT NULL
            CHECK(role IN ('ADMIN','CA','ACCOUNTANT','MANAGER')),
          company_id TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          FOREIGN KEY(company_id) REFERENCES companies(id)
        )
      ''');

      // ── 4. Cheque columns on payments ───────────────────────────────────
      // Guard: only add if table exists and not already present (safe re-run)
      final paymentsExist = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='payments'"
      )).isNotEmpty;

      if (paymentsExist) {
        final paymentInfo = await db.rawQuery("PRAGMA table_info(payments)");
        final existingCols = paymentInfo.map((r) => r['name'] as String).toSet();
        if (!existingCols.contains('cheque_no')) {
          await db.execute('ALTER TABLE payments ADD COLUMN cheque_no TEXT');
        }
        if (!existingCols.contains('cheque_bank')) {
          await db.execute('ALTER TABLE payments ADD COLUMN cheque_bank TEXT');
        }
        if (!existingCols.contains('cheque_date')) {
          await db.execute('ALTER TABLE payments ADD COLUMN cheque_date TEXT');
        }
        if (!existingCols.contains('cheque_status')) {
          await db.execute(
              "ALTER TABLE payments ADD COLUMN cheque_status TEXT "
              "CHECK(cheque_status IN ('ISSUED','CLEARED','BOUNCED','CANCELLED'))");
        }
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Items table
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

    // 2. Parties table
    await db.execute('''
      CREATE TABLE parties (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT CHECK(type IN ('SUPPLIER', 'CUSTOMER')) NOT NULL,
        phone TEXT NOT NULL,
        address TEXT NOT NULL,
        gstin TEXT,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        balance_type TEXT CHECK(balance_type IN ('DR', 'CR')) NOT NULL DEFAULT 'CR',
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 3. Purchases table
    await db.execute('''
      CREATE TABLE purchases (
        id TEXT PRIMARY KEY,
        invoice_no TEXT UNIQUE NOT NULL,
        party_id TEXT NOT NULL,
        date TEXT NOT NULL,
        subtotal REAL NOT NULL,
        gst_total REAL NOT NULL,
        grand_total REAL NOT NULL,
        payment_status TEXT CHECK(payment_status IN ('PAID', 'PARTIAL', 'PENDING')) NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        edit_history TEXT,
        category TEXT CHECK(category IN ('SEED', 'FERTILISER')) NOT NULL,
        FOREIGN KEY(party_id) REFERENCES parties(id)
      )
    ''');

    // 4. Purchase Items table
    await db.execute('''
      CREATE TABLE purchase_items (
        id TEXT PRIMARY KEY,
        purchase_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        qty REAL NOT NULL,
        rate REAL NOT NULL,
        gst_rate REAL NOT NULL,
        gst_amt REAL NOT NULL,
        total REAL NOT NULL,
        lot_no TEXT,
        hsn_code TEXT,
        no_of_pkts REAL,
        no_of_bags REAL,
        per_unit TEXT,
        discount_pct REAL,
        mfg_date TEXT,
        exp_date TEXT,
        manufacturer TEXT,
        packing TEXT,
        unit_per_case REAL,
        no_of_cases REAL,
        total_units REAL,
        unit_price REAL,
        FOREIGN KEY(purchase_id) REFERENCES purchases(id),
        FOREIGN KEY(item_id) REFERENCES items(id)
      )
    ''');

    // 5. Sales table
    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        invoice_no TEXT UNIQUE NOT NULL,
        party_id TEXT NOT NULL,
        date TEXT NOT NULL,
        subtotal REAL NOT NULL,
        gst_total REAL NOT NULL,
        grand_total REAL NOT NULL,
        payment_status TEXT CHECK(payment_status IN ('PAID', 'PARTIAL', 'PENDING')) NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        edit_history TEXT,
        category TEXT CHECK(category IN ('SEED', 'FERTILISER')) NOT NULL,
        FOREIGN KEY(party_id) REFERENCES parties(id)
      )
    ''');

    // 6. Sale Items table
    await db.execute('''
      CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        qty REAL NOT NULL,
        rate REAL NOT NULL,
        gst_rate REAL NOT NULL,
        gst_amt REAL NOT NULL,
        total REAL NOT NULL,
        manufacturer TEXT,
        packing TEXT,
        batch_no TEXT,
        hsn_code TEXT,
        mfg_date TEXT,
        exp_date TEXT,
        unit_per_case REAL,
        no_of_cases REAL,
        total_units REAL,
        unit_price REAL,
        FOREIGN KEY(sale_id) REFERENCES sales(id),
        FOREIGN KEY(item_id) REFERENCES items(id)
      )
    ''');

    // 7. Payments table
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        party_id TEXT NOT NULL,
        direction TEXT CHECK(direction IN ('RECEIVED', 'PAID')) NOT NULL,
        amount REAL NOT NULL,
        mode TEXT CHECK(mode IN ('CASH', 'UPI', 'BANK', 'CHEQUE')) NOT NULL,
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

    // 8. Audit Logs table
    await db.execute('''
      CREATE TABLE audit_logs (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        action TEXT CHECK(action IN ('CREATE', 'EDIT', 'DELETE')) NOT NULL,
        old_values TEXT,
        new_values TEXT,
        timestamp TEXT NOT NULL,
        device_id TEXT NOT NULL
      )
    ''');

    // 9. Backup Metas table
    await db.execute('''
      CREATE TABLE backup_metas (
        id TEXT PRIMARY KEY,
        timestamp TEXT NOT NULL,
        gdrive_file_id TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        status TEXT CHECK(status IN ('SUCCESS', 'FAILED')) NOT NULL,
        device_id TEXT NOT NULL
      )
    ''');

    // 10. Sync Queue table
    await db.execute('''
      CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY,
        operation TEXT CHECK(operation IN ('CREATE','EDIT','DELETE')) NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        field_name TEXT DEFAULT '_full_row',
        old_value TEXT,
        new_value TEXT,
        payload TEXT,
        created_at TEXT NOT NULL,
        device_role TEXT DEFAULT 'owner',
        is_resolution INTEGER DEFAULT 0,
        status TEXT CHECK(
          status IN ('PENDING','DONE','FAILED','SUPERSEDED')
        ) NOT NULL DEFAULT 'PENDING'
      )
    ''');

    // 11. Settings table
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 12. Expenses table
    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        category TEXT CHECK(category IN ('RENT', 'ELECTRICITY', 'SALARY', 'HAMALI', 'MAINTENANCE', 'FUEL', 'OTHER')) NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        description TEXT NOT NULL,
        payment_method TEXT CHECK(payment_method IN ('CASH', 'BANK')) NOT NULL DEFAULT 'CASH',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Prepopulate default settings
    await db.insert('settings', {'key': 'state', 'value': 'Telangana'});
    await db.insert('settings', {'key': 'state_code', 'value': '36'});

    // 13. Companies table
    await db.execute('''
      CREATE TABLE companies (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        gstin TEXT,
        address TEXT,
        phone TEXT,
        state TEXT NOT NULL DEFAULT 'Telangana',
        state_code TEXT NOT NULL DEFAULT '36',
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    // Seed default company (will be updated when user fills Settings)
    await db.insert('companies', {
      'id': 'company_default',
      'name': 'My Company',
      'gstin': null,
      'address': null,
      'phone': null,
      'state': 'Telangana',
      'state_code': '36',
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    // 14. Financial Years table
    await db.execute('''
      CREATE TABLE financial_years (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL,
        label TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        is_locked INTEGER NOT NULL DEFAULT 0,
        locked_by TEXT,
        locked_at TEXT,
        FOREIGN KEY(company_id) REFERENCES companies(id)
      )
    ''');

    // Seed current financial year
    final now = DateTime.now();
    final fyStart = now.month >= 4
        ? DateTime(now.year, 4, 1)
        : DateTime(now.year - 1, 4, 1);
    final fyEnd = DateTime(fyStart.year + 1, 3, 31);
    final fyLabel =
        'FY ${fyStart.year.toString().substring(2)}-${fyEnd.year.toString().substring(2)}';
    await db.insert('financial_years', {
      'id': 'fy_default',
      'company_id': 'company_default',
      'label': fyLabel,
      'start_date': '${fyStart.year}-04-01',
      'end_date': '${fyEnd.year}-03-31',
      'is_locked': 0,
      'locked_by': null,
      'locked_at': null,
    });

    // 15. App Users table
    await db.execute('''
      CREATE TABLE app_users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        role TEXT NOT NULL
          CHECK(role IN ('ADMIN','CA','ACCOUNTANT','MANAGER')),
        company_id TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY(company_id) REFERENCES companies(id)
      )
    ''');

    // 16. Sync Conflicts table
    await db.execute('''
      CREATE TABLE sync_conflicts (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        local_value TEXT NOT NULL,
        local_device TEXT NOT NULL,
        local_timestamp TEXT NOT NULL,
        remote_value TEXT NOT NULL,
        remote_device TEXT NOT NULL,
        remote_timestamp TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK(status IN ('pending', 'resolved', 'superseded')),
        resolved_value TEXT,
        resolved_by TEXT,
        resolved_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // 17. Conflict Audit Log table
    await db.execute('''
      CREATE TABLE conflict_audit_log (
        id TEXT PRIMARY KEY,
        conflict_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        field_name TEXT NOT NULL,
        winning_value TEXT,
        losing_value TEXT,
        resolved_by TEXT NOT NULL,
        resolved_at TEXT NOT NULL,
        resolution_source TEXT NOT NULL
          CHECK(resolution_source IN ('local', 'remote_sync'))
      )
    ''');
  }

  /// Close connection
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Clears the local database by deleting the file (used on logout/logoff)
  Future<void> clearDatabase() async {
    final String path = join(await getDatabasesPath(), 'godown_management.db');
    await close();
    await deleteDatabase(path);
  }
}
