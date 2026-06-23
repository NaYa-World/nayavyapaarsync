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
      version: 14,
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

    if (oldVersion < 9) {
      final paymentsExist = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='payments'"
      )).isNotEmpty;

      if (paymentsExist) {
        // Recreate payments table to update check constraint and indexes
        await db.execute('ALTER TABLE payments RENAME TO payments_old');

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
            cheque_status TEXT CHECK(cheque_status IN ('ISSUED','RECEIVED','PENDING','CLEARED','BOUNCED','CANCELLED')),
            FOREIGN KEY(party_id) REFERENCES parties(id)
          )
        ''');

        await db.execute('''
          INSERT INTO payments (
            id, party_id, direction, amount, mode, date, reference_no,
            linked_invoice_id, notes, created_at, is_deleted,
            cheque_no, cheque_bank, cheque_date, cheque_status
          )
          SELECT 
            id, party_id, direction, amount, mode, date, reference_no,
            linked_invoice_id, notes, created_at, is_deleted,
            cheque_no, cheque_bank, cheque_date, cheque_status
          FROM payments_old
        ''');

        await db.execute('DROP TABLE payments_old');
      } else {
        // Just create the table if it didn't exist
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
            cheque_status TEXT CHECK(cheque_status IN ('ISSUED','RECEIVED','PENDING','CLEARED','BOUNCED','CANCELLED')),
            FOREIGN KEY(party_id) REFERENCES parties(id)
          )
        ''');
      }

      // Create indexes for optimization (only if tables exist)
      final existingTables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
      )).map((row) => row['name'] as String).toSet();

      if (existingTables.contains('payments')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_party_id ON payments(party_id)');
      }
      if (existingTables.contains('purchases')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchases_party_id ON purchases(party_id)');
      }
      if (existingTables.contains('sales')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_party_id ON sales(party_id)');
      }
      if (existingTables.contains('financial_years')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_financial_years_company_id ON financial_years(company_id)');
      }
      if (existingTables.contains('app_users')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_app_users_company_id ON app_users(company_id)');
      }
    }

    if (oldVersion < 10) {
      // 1. Ledger Groups
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ledger_groups (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          parent_id TEXT,
          nature TEXT CHECK(nature IN ('ASSETS', 'LIABILITIES', 'INCOME', 'EXPENSES')) NOT NULL,
          FOREIGN KEY(parent_id) REFERENCES ledger_groups(id)
        )
      ''');

      // 2. Ledgers
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ledgers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          group_id TEXT NOT NULL,
          opening_balance REAL NOT NULL DEFAULT 0.0,
          balance_type TEXT CHECK(balance_type IN ('DR', 'CR')) NOT NULL DEFAULT 'DR',
          company_id TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          FOREIGN KEY(group_id) REFERENCES ledger_groups(id),
          FOREIGN KEY(company_id) REFERENCES companies(id)
        )
      ''');

      // 3. Vouchers
      await db.execute('''
        CREATE TABLE IF NOT EXISTS vouchers (
          id TEXT PRIMARY KEY,
          voucher_no TEXT NOT NULL,
          type TEXT CHECK(type IN ('SALE', 'PURCHASE', 'RECEIPT', 'PAYMENT', 'CONTRA', 'JOURNAL', 'CREDIT_NOTE', 'DEBIT_NOTE')) NOT NULL,
          date TEXT NOT NULL,
          narration TEXT,
          company_id TEXT NOT NULL,
          fy_id TEXT NOT NULL,
          is_locked INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY(company_id) REFERENCES companies(id),
          FOREIGN KEY(fy_id) REFERENCES financial_years(id)
        )
      ''');

      // 4. Voucher Lines
      await db.execute('''
        CREATE TABLE IF NOT EXISTS voucher_lines (
          id TEXT PRIMARY KEY,
          voucher_id TEXT NOT NULL,
          ledger_id TEXT NOT NULL,
          dr_amount REAL NOT NULL DEFAULT 0.0,
          cr_amount REAL NOT NULL DEFAULT 0.0,
          narration TEXT,
          FOREIGN KEY(voucher_id) REFERENCES vouchers(id) ON DELETE CASCADE,
          FOREIGN KEY(ledger_id) REFERENCES ledgers(id)
        )
      ''');

      // 5. Bill Allocations
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bill_allocations (
          id TEXT PRIMARY KEY,
          voucher_line_id TEXT NOT NULL,
          ref_voucher_id TEXT NOT NULL,
          allocated_amount REAL NOT NULL,
          outstanding_amount REAL NOT NULL,
          status TEXT CHECK(status IN ('OPEN', 'PART_PAID', 'CLOSED')) NOT NULL DEFAULT 'OPEN',
          FOREIGN KEY(voucher_line_id) REFERENCES voucher_lines(id) ON DELETE CASCADE,
          FOREIGN KEY(ref_voucher_id) REFERENCES vouchers(id)
        )
      ''');

      // 6. Godowns
      await db.execute('''
        CREATE TABLE IF NOT EXISTS godowns (
          id TEXT PRIMARY KEY,
          company_id TEXT NOT NULL,
          name TEXT NOT NULL,
          address TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          FOREIGN KEY(company_id) REFERENCES companies(id)
        )
      ''');

      // 7. Batches
      await db.execute('''
        CREATE TABLE IF NOT EXISTS batches (
          id TEXT PRIMARY KEY,
          stock_item_id TEXT NOT NULL,
          batch_no TEXT NOT NULL,
          expiry_date TEXT,
          mfg_date TEXT,
          FOREIGN KEY(stock_item_id) REFERENCES items(id)
        )
      ''');

      // 8. Stock Movements
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_movements (
          id TEXT PRIMARY KEY,
          stock_item_id TEXT NOT NULL,
          godown_id TEXT NOT NULL,
          ref_voucher_id TEXT NOT NULL,
          qty REAL NOT NULL,
          rate REAL NOT NULL,
          movement_type TEXT CHECK(movement_type IN ('IN', 'OUT')) NOT NULL,
          batch_id TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY(stock_item_id) REFERENCES items(id),
          FOREIGN KEY(godown_id) REFERENCES godowns(id),
          FOREIGN KEY(ref_voucher_id) REFERENCES vouchers(id) ON DELETE CASCADE,
          FOREIGN KEY(batch_id) REFERENCES batches(id)
        )
      ''');

      // 9. Bank Instruments
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bank_instruments (
          id TEXT PRIMARY KEY,
          voucher_id TEXT NOT NULL,
          instrument_type TEXT CHECK(instrument_type IN ('CHEQUE', 'DD', 'NEFT', 'RTGS', 'UPI')) NOT NULL,
          instrument_no TEXT,
          bank_name TEXT,
          amount REAL NOT NULL,
          status TEXT CHECK(status IN ('ISSUED', 'RECEIVED', 'PENDING', 'CLEARED', 'BOUNCED', 'CANCELLED')) NOT NULL DEFAULT 'PENDING',
          cleared_date TEXT,
          FOREIGN KEY(voucher_id) REFERENCES vouchers(id) ON DELETE CASCADE
        )
      ''');

      // 10. Bank Reconciliation
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bank_reconciliation (
          id TEXT PRIMARY KEY,
          ledger_id TEXT NOT NULL,
          statement_date TEXT NOT NULL,
          closing_balance_bank REAL NOT NULL,
          closing_balance_book REAL NOT NULL,
          difference REAL NOT NULL,
          reconciled_by TEXT NOT NULL,
          reconciled_at TEXT NOT NULL,
          FOREIGN KEY(ledger_id) REFERENCES ledgers(id)
        )
      ''');

      // 11. Virtual Tables (FTS5 with FTS4 fallback)
      final useFts5 = await _supportsFts5(db);
      final ftsModule = useFts5 ? 'fts5' : 'fts4';
      await db.execute('CREATE VIRTUAL TABLE IF NOT EXISTS fts_vouchers USING $ftsModule(voucher_id, narration, voucher_no)');
      await db.execute('CREATE VIRTUAL TABLE IF NOT EXISTS fts_ledgers USING $ftsModule(ledger_id, name)');

      // 12. Indexes
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_company_date ON vouchers(company_id, date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_voucher_lines_voucher ON voucher_lines(voucher_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_item ON stock_movements(stock_item_id)');
    }

    if (oldVersion < 11) {
      // 1. Alter app_users table to add salt column (if table exists)
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='app_users'"
      );
      if (tables.isNotEmpty) {
        await db.execute('ALTER TABLE app_users ADD COLUMN salt TEXT');
      }

      // 2. Create triggers for vouchers -> fts_vouchers
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_vouchers_fts_insert AFTER INSERT ON vouchers
        BEGIN
          INSERT INTO fts_vouchers(voucher_id, narration, voucher_no)
          VALUES(new.id, COALESCE(new.narration, ''), new.voucher_no);
        END;
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_vouchers_fts_update AFTER UPDATE ON vouchers
        BEGIN
          UPDATE fts_vouchers
          SET narration = COALESCE(new.narration, ''),
              voucher_no = new.voucher_no
          WHERE voucher_id = new.id;
        END;
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_vouchers_fts_delete AFTER DELETE ON vouchers
        BEGIN
          DELETE FROM fts_vouchers WHERE voucher_id = old.id;
        END;
      ''');

      // 3. Create triggers for ledgers -> fts_ledgers
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_ledgers_fts_insert AFTER INSERT ON ledgers
        BEGIN
          INSERT INTO fts_ledgers(ledger_id, name)
          VALUES(new.id, new.name);
        END;
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_ledgers_fts_update AFTER UPDATE ON ledgers
        BEGIN
          UPDATE fts_ledgers
          SET name = new.name
          WHERE ledger_id = new.id;
        END;
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_ledgers_fts_delete AFTER DELETE ON ledgers
        BEGIN
          DELETE FROM fts_ledgers WHERE ledger_id = old.id;
        END;
      ''');

      // 4. Backfill existing data
      await db.execute('DELETE FROM fts_vouchers');
      await db.execute('DELETE FROM fts_ledgers');

      await db.execute('''
        INSERT INTO fts_vouchers(voucher_id, narration, voucher_no)
        SELECT id, COALESCE(narration, ''), voucher_no FROM vouchers
      ''');

      await db.execute('''
        INSERT INTO fts_ledgers(ledger_id, name)
        SELECT id, name FROM ledgers
      ''');
    }

    if (oldVersion < 12) {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='items'"
      );
      if (tables.isNotEmpty) {
        await db.execute("ALTER TABLE items ADD COLUMN stock_group TEXT DEFAULT 'General'");
      }
    }

    if (oldVersion < 13) {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='vouchers'"
      );
      if (tables.isNotEmpty) {
        await db.execute("ALTER TABLE vouchers ADD COLUMN is_cancelled INTEGER NOT NULL DEFAULT 0");
      }
    }

    if (oldVersion < 14) {
      final List<String> legacyTables = ['sales', 'purchases', 'payments', 'expenses', 'parties', 'items'];
      for (final table in legacyTables) {
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'"
        );
        if (tables.isNotEmpty) {
          final columns = await db.rawQuery("PRAGMA table_info($table)");
          final existingCols = columns.map((r) => r['name'] as String).toSet();
          if (!existingCols.contains('company_id')) {
            await db.execute("ALTER TABLE $table ADD COLUMN company_id TEXT DEFAULT 'company_default'");
          }
        }
      }

      Future<bool> hasColumn(String tbl, String col) async {
        final t = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='$tbl'"
        );
        if (t.isEmpty) return false;
        final cols = await db.rawQuery("PRAGMA table_info($tbl)");
        return cols.any((r) => r['name'] == col);
      }

      if (await hasColumn('purchase_items', 'item_id')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_item_id ON purchase_items(item_id)');
      }
      if (await hasColumn('sale_items', 'item_id')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_item_id ON sale_items(item_id)');
      }
      if (await hasColumn('purchases', 'company_id')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchases_company ON purchases(company_id)');
      }
      if (await hasColumn('sales', 'company_id')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_company ON sales(company_id)');
      }
      if (await hasColumn('payments', 'company_id')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_company ON payments(company_id)');
      }
      if (await hasColumn('expenses', 'company_id')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_company ON expenses(company_id)');
      }
      if (await hasColumn('parties', 'company_id')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_parties_company ON parties(company_id)');
      }
      if (await hasColumn('items', 'company_id')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_items_company ON items(company_id)');
      }
      if (await hasColumn('purchases', 'is_deleted')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchases_is_deleted ON purchases(id, is_deleted)');
      }
      if (await hasColumn('sales', 'is_deleted')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_is_deleted ON sales(id, is_deleted)');
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_balances (
          item_id TEXT PRIMARY KEY,
          qty REAL NOT NULL DEFAULT 0.0
        )
      ''');

      if (await hasColumn('purchase_items', 'qty') &&
          await hasColumn('purchases', 'is_deleted') &&
          await hasColumn('sale_items', 'qty') &&
          await hasColumn('sales', 'is_deleted')) {
        await db.execute('''
          INSERT OR REPLACE INTO stock_balances (item_id, qty)
          SELECT item_id, SUM(qty) FROM (
            SELECT pi.item_id, pi.qty FROM purchase_items pi
            JOIN purchases p ON pi.purchase_id = p.id
            WHERE p.is_deleted = 0
            UNION ALL
            SELECT si.item_id, -si.qty FROM sale_items si
            JOIN sales s ON si.sale_id = s.id
            WHERE s.is_deleted = 0
          ) GROUP BY item_id
        ''');
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
        is_deleted INTEGER NOT NULL DEFAULT 0,
        stock_group TEXT DEFAULT 'General',
        company_id TEXT NOT NULL DEFAULT 'company_default'
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
        is_deleted INTEGER NOT NULL DEFAULT 0,
        company_id TEXT NOT NULL DEFAULT 'company_default'
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
        company_id TEXT NOT NULL DEFAULT 'company_default',
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
        company_id TEXT NOT NULL DEFAULT 'company_default',
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
        cheque_status TEXT CHECK(cheque_status IN ('ISSUED','RECEIVED','PENDING','CLEARED','BOUNCED','CANCELLED')),
        company_id TEXT NOT NULL DEFAULT 'company_default',
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
        is_deleted INTEGER NOT NULL DEFAULT 0,
        company_id TEXT NOT NULL DEFAULT 'company_default'
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
        salt TEXT,
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

    // Indexes for optimization
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_party_id ON payments(party_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchases_party_id ON purchases(party_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_party_id ON sales(party_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_financial_years_company_id ON financial_years(company_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_app_users_company_id ON app_users(company_id)');

    // Version 10 Tables
    await db.execute('''
      CREATE TABLE ledger_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT,
        nature TEXT CHECK(nature IN ('ASSETS', 'LIABILITIES', 'INCOME', 'EXPENSES')) NOT NULL,
        FOREIGN KEY(parent_id) REFERENCES ledger_groups(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE ledgers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        group_id TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        balance_type TEXT CHECK(balance_type IN ('DR', 'CR')) NOT NULL DEFAULT 'DR',
        company_id TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY(group_id) REFERENCES ledger_groups(id),
        FOREIGN KEY(company_id) REFERENCES companies(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE vouchers (
        id TEXT PRIMARY KEY,
        voucher_no TEXT NOT NULL,
        type TEXT CHECK(type IN ('SALE', 'PURCHASE', 'RECEIPT', 'PAYMENT', 'CONTRA', 'JOURNAL', 'CREDIT_NOTE', 'DEBIT_NOTE')) NOT NULL,
        date TEXT NOT NULL,
        narration TEXT,
        company_id TEXT NOT NULL,
        fy_id TEXT NOT NULL,
        is_locked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_cancelled INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(company_id) REFERENCES companies(id),
        FOREIGN KEY(fy_id) REFERENCES financial_years(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE voucher_lines (
        id TEXT PRIMARY KEY,
        voucher_id TEXT NOT NULL,
        ledger_id TEXT NOT NULL,
        dr_amount REAL NOT NULL DEFAULT 0.0,
        cr_amount REAL NOT NULL DEFAULT 0.0,
        narration TEXT,
        FOREIGN KEY(voucher_id) REFERENCES vouchers(id) ON DELETE CASCADE,
        FOREIGN KEY(ledger_id) REFERENCES ledgers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE bill_allocations (
        id TEXT PRIMARY KEY,
        voucher_line_id TEXT NOT NULL,
        ref_voucher_id TEXT NOT NULL,
        allocated_amount REAL NOT NULL,
        outstanding_amount REAL NOT NULL,
        status TEXT CHECK(status IN ('OPEN', 'PART_PAID', 'CLOSED')) NOT NULL DEFAULT 'OPEN',
        FOREIGN KEY(voucher_line_id) REFERENCES voucher_lines(id) ON DELETE CASCADE,
        FOREIGN KEY(ref_voucher_id) REFERENCES vouchers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE godowns (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL,
        name TEXT NOT NULL,
        address TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY(company_id) REFERENCES companies(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE batches (
        id TEXT PRIMARY KEY,
        stock_item_id TEXT NOT NULL,
        batch_no TEXT NOT NULL,
        expiry_date TEXT,
        mfg_date TEXT,
        FOREIGN KEY(stock_item_id) REFERENCES items(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        stock_item_id TEXT NOT NULL,
        godown_id TEXT NOT NULL,
        ref_voucher_id TEXT NOT NULL,
        qty REAL NOT NULL,
        rate REAL NOT NULL,
        movement_type TEXT CHECK(movement_type IN ('IN', 'OUT')) NOT NULL,
        batch_id TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(stock_item_id) REFERENCES items(id),
        FOREIGN KEY(godown_id) REFERENCES godowns(id),
        FOREIGN KEY(ref_voucher_id) REFERENCES vouchers(id) ON DELETE CASCADE,
        FOREIGN KEY(batch_id) REFERENCES batches(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE bank_instruments (
        id TEXT PRIMARY KEY,
        voucher_id TEXT NOT NULL,
        instrument_type TEXT CHECK(instrument_type IN ('CHEQUE', 'DD', 'NEFT', 'RTGS', 'UPI')) NOT NULL,
        instrument_no TEXT,
        bank_name TEXT,
        amount REAL NOT NULL,
        status TEXT CHECK(status IN ('ISSUED', 'RECEIVED', 'PENDING', 'CLEARED', 'BOUNCED', 'CANCELLED')) NOT NULL DEFAULT 'PENDING',
        cleared_date TEXT,
        FOREIGN KEY(voucher_id) REFERENCES vouchers(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE bank_reconciliation (
        id TEXT PRIMARY KEY,
        ledger_id TEXT NOT NULL,
        statement_date TEXT NOT NULL,
        closing_balance_bank REAL NOT NULL,
        closing_balance_book REAL NOT NULL,
        difference REAL NOT NULL,
        reconciled_by TEXT NOT NULL,
        reconciled_at TEXT NOT NULL,
        FOREIGN KEY(ledger_id) REFERENCES ledgers(id)
      )
    ''');

    final useFts5 = await _supportsFts5(db);
    final ftsModule = useFts5 ? 'fts5' : 'fts4';
    await db.execute('CREATE VIRTUAL TABLE fts_vouchers USING $ftsModule(voucher_id, narration, voucher_no)');
    await db.execute('CREATE VIRTUAL TABLE fts_ledgers USING $ftsModule(ledger_id, name)');

    // Create SQL Triggers for FTS sync
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_vouchers_fts_insert AFTER INSERT ON vouchers
      BEGIN
        INSERT INTO fts_vouchers(voucher_id, narration, voucher_no)
        VALUES(new.id, COALESCE(new.narration, ''), new.voucher_no);
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_vouchers_fts_update AFTER UPDATE ON vouchers
      BEGIN
        UPDATE fts_vouchers
        SET narration = COALESCE(new.narration, ''),
            voucher_no = new.voucher_no
        WHERE voucher_id = new.id;
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_vouchers_fts_delete AFTER DELETE ON vouchers
      BEGIN
        DELETE FROM fts_vouchers WHERE voucher_id = old.id;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_ledgers_fts_insert AFTER INSERT ON ledgers
      BEGIN
        INSERT INTO fts_ledgers(ledger_id, name)
        VALUES(new.id, new.name);
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_ledgers_fts_update AFTER UPDATE ON ledgers
      BEGIN
        UPDATE fts_ledgers
        SET name = new.name
        WHERE ledger_id = new.id;
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_ledgers_fts_delete AFTER DELETE ON ledgers
      BEGIN
        DELETE FROM fts_ledgers WHERE ledger_id = old.id;
      END;
    ''');

    await db.execute('CREATE INDEX idx_vouchers_company_date ON vouchers(company_id, date)');
    await db.execute('CREATE INDEX idx_voucher_lines_voucher ON voucher_lines(voucher_id)');
    await db.execute('CREATE INDEX idx_stock_movements_item ON stock_movements(stock_item_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_balances (
        item_id TEXT PRIMARY KEY,
        qty REAL NOT NULL DEFAULT 0.0
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_item_id ON purchase_items(item_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_item_id ON sale_items(item_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchases_company ON purchases(company_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_company ON sales(company_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_company ON payments(company_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_company ON expenses(company_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_parties_company ON parties(company_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_company ON items(company_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchases_is_deleted ON purchases(id, is_deleted)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_is_deleted ON sales(id, is_deleted)');
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

  /// Checks if FTS5 module is supported/enabled in the current SQLite environment
  Future<bool> _supportsFts5(Database db) async {
    try {
      final modules = await db.rawQuery("SELECT name FROM pragma_module_list WHERE name = 'fts5'");
      return modules.isNotEmpty;
    } catch (_) {
      try {
        final result = await db.rawQuery("SELECT sqlite_compileoption_used('ENABLE_FTS5') AS fts5");
        if (result.isNotEmpty && result.first['fts5'] == 1) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }
}
