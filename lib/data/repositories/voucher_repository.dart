import '../database/db_helper.dart';
import '../models/voucher.dart';
import '../models/voucher_line.dart';
import '../models/bill_allocation.dart';

class VoucherRepository {
  final DbHelper _dbHelper = DbHelper();

  // ─── Vouchers ──────────────────────────────────────────────────────────────

  Future<void> insertVoucher(Voucher voucher, List<VoucherLine> lines) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('vouchers', voucher.toMap());
      for (final line in lines) {
        await txn.insert('voucher_lines', line.toMap());
      }
    });
  }

  Future<void> updateVoucher(Voucher voucher, List<VoucherLine> lines) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        'vouchers',
        voucher.toMap(),
        where: 'id = ?',
        whereArgs: [voucher.id],
      );
      // Delete old lines (ON DELETE CASCADE is on actual delete, but we can clear them manually for safety)
      await txn.delete(
        'voucher_lines',
        where: 'voucher_id = ?',
        whereArgs: [voucher.id],
      );
      for (final line in lines) {
        await txn.insert('voucher_lines', line.toMap());
      }
    });
  }

  Future<void> deleteVoucher(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'vouchers',
      {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Voucher>> getVouchers({String? companyId, String? fyId, bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (companyId != null && fyId != null) {
      whereClause = activeOnly ? 'company_id = ? AND fy_id = ? AND is_deleted = 0' : 'company_id = ? AND fy_id = ?';
      whereArgs = [companyId, fyId];
    } else if (companyId != null) {
      whereClause = activeOnly ? 'company_id = ? AND is_deleted = 0' : 'company_id = ?';
      whereArgs = [companyId];
    }

    final rows = await db.query(
      'vouchers',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date DESC, created_at DESC',
    );
    return rows.map(Voucher.fromMap).toList();
  }

  Future<Voucher?> getVoucherById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('vouchers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Voucher.fromMap(rows.first);
  }

  // ─── Voucher Lines ─────────────────────────────────────────────────────────

  Future<List<VoucherLine>> getVoucherLines(String voucherId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('voucher_lines', where: 'voucher_id = ?', whereArgs: [voucherId]);
    return rows.map(VoucherLine.fromMap).toList();
  }

  // ─── Bill Allocations ──────────────────────────────────────────────────────

  Future<void> insertBillAllocation(BillAllocation allocation) async {
    final db = await _dbHelper.database;
    await db.insert('bill_allocations', allocation.toMap());
  }

  Future<List<BillAllocation>> getBillAllocations(String voucherLineId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('bill_allocations', where: 'voucher_line_id = ?', whereArgs: [voucherLineId]);
    return rows.map(BillAllocation.fromMap).toList();
  }

  // ─── FTS5 Search ───────────────────────────────────────────────────────────

  Future<List<Voucher>> searchVouchers({required String companyId, required String queryText}) async {
    if (queryText.trim().isEmpty) return getVouchers(companyId: companyId);
    final db = await _dbHelper.database;
    final sanitizedQuery = queryText.replaceAll(RegExp(r'[^\w\s]'), '');
    if (sanitizedQuery.trim().isEmpty) return [];

    final rows = await db.rawQuery('''
      SELECT v.* FROM vouchers v
      JOIN fts_vouchers f ON v.id = f.voucher_id
      WHERE fts_vouchers MATCH ? AND v.company_id = ? AND v.is_deleted = 0
      ORDER BY v.date DESC, v.created_at DESC
    ''', ['$sanitizedQuery*', companyId]);
    return rows.map(Voucher.fromMap).toList();
  }
}
