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
      version: 4,
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
        operation TEXT CHECK(operation IN ('CREATE', 'EDIT', 'DELETE')) NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        payload TEXT,
        created_at TEXT NOT NULL,
        status TEXT CHECK(status IN ('PENDING', 'DONE', 'FAILED')) NOT NULL DEFAULT 'PENDING'
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
  }

  /// Close connection
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
