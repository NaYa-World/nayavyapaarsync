import '../database/db_helper.dart';
import '../models/ledger.dart';
import '../models/ledger_group.dart';

class LedgerRepository {
  final DbHelper _dbHelper = DbHelper();

  // ─── Ledger Groups ─────────────────────────────────────────────────────────

  Future<void> createLedgerGroup(LedgerGroup group) async {
    final db = await _dbHelper.database;
    await db.insert('ledger_groups', group.toMap());
  }

  Future<List<LedgerGroup>> getLedgerGroups() async {
    final db = await _dbHelper.database;
    final rows = await db.query('ledger_groups', orderBy: 'name ASC');
    return rows.map(LedgerGroup.fromMap).toList();
  }

  // ─── Ledgers ───────────────────────────────────────────────────────────────

  Future<void> createLedger(Ledger ledger) async {
    final db = await _dbHelper.database;
    await db.insert('ledgers', ledger.toMap());
  }

  Future<List<Ledger>> getLedgers({String? companyId, bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (companyId != null) {
      whereClause = activeOnly ? 'company_id = ? AND is_active = 1' : 'company_id = ?';
      whereArgs = [companyId];
    } else if (activeOnly) {
      whereClause = 'is_active = 1';
    }

    final rows = await db.query(
      'ledgers',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );
    return rows.map(Ledger.fromMap).toList();
  }

  Future<Ledger?> getLedgerById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('ledgers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Ledger.fromMap(rows.first);
  }

  Future<void> deactivateLedger(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'ledgers',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── FTS5 Search ───────────────────────────────────────────────────────────

  Future<List<Ledger>> searchLedgers({required String companyId, required String queryText, bool activeOnly = true}) async {
    if (queryText.trim().isEmpty) return getLedgers(companyId: companyId, activeOnly: activeOnly);
    final db = await _dbHelper.database;
    final sanitizedQuery = queryText.replaceAll(RegExp(r'[^\w\s]'), '');
    if (sanitizedQuery.trim().isEmpty) return [];

    final activeFilter = activeOnly ? 'AND l.is_active = 1' : '';
    final rows = await db.rawQuery('''
      SELECT l.* FROM ledgers l
      JOIN fts_ledgers f ON l.id = f.ledger_id
      WHERE fts_ledgers MATCH ? AND l.company_id = ? $activeFilter
      ORDER BY l.name ASC
    ''', ['$sanitizedQuery*', companyId]);
    return rows.map(Ledger.fromMap).toList();
  }
}
