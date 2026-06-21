import '../database/db_helper.dart';
import '../models/bank_instrument.dart';
import '../models/bank_reconciliation.dart';

class BrsRepository {
  final DbHelper _dbHelper = DbHelper();

  // ─── Bank Instruments ──────────────────────────────────────────────────────

  Future<void> insertBankInstrument(BankInstrument instrument) async {
    final db = await _dbHelper.database;
    await db.insert('bank_instruments', instrument.toMap());
  }

  Future<List<BankInstrument>> getBankInstruments(String voucherId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'bank_instruments',
      where: 'voucher_id = ?',
      whereArgs: [voucherId],
    );
    return rows.map(BankInstrument.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getUnclearedInstruments(String bankLedgerId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT bi.*, v.date as voucher_date, v.voucher_no
      FROM bank_instruments bi
      JOIN vouchers v ON bi.voucher_id = v.id
      JOIN voucher_lines vl ON vl.voucher_id = v.id
      WHERE vl.ledger_id = ? AND bi.status != 'CLEARED' AND v.is_deleted = 0 AND v.is_cancelled = 0
    ''', [bankLedgerId]);
    return rows;
  }

  Future<void> updateInstrumentStatus(String instrumentId, String status, DateTime? clearedDate) async {
    final db = await _dbHelper.database;
    await db.update(
      'bank_instruments',
      {
        'status': status,
        'cleared_date': clearedDate?.toIso8601String().substring(0, 10),
      },
      where: 'id = ?',
      whereArgs: [instrumentId],
    );
  }

  // ─── Bank Reconciliation ───────────────────────────────────────────────────

  Future<void> insertBankReconciliation(BankReconciliation reconciliation) async {
    final db = await _dbHelper.database;
    await db.insert('bank_reconciliation', reconciliation.toMap());
  }

  Future<BankReconciliation?> getLatestReconciliation(String bankLedgerId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'bank_reconciliation',
      where: 'ledger_id = ?',
      whereArgs: [bankLedgerId],
      orderBy: 'statement_date DESC, reconciled_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BankReconciliation.fromMap(rows.first);
  }
}
