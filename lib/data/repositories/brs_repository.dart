import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/bank_instrument.dart';
import '../models/bank_reconciliation.dart';

class BrsRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  // ─── Bank Instruments ──────────────────────────────────────────────────────

  Future<void> insertBankInstrument(BankInstrument instrument, {String deviceId = 'unknown_device'}) async {
    final db = await _dbHelper.database;
    final map = instrument.toMap();
    await db.transaction((txn) async {
      await txn.insert('bank_instruments', map);

      await _dbHelper.insertAuditLog(
        txn,
        id: _uuid.v4(),
        tableName: 'bank_instruments',
        recordId: instrument.id,
        action: 'CREATE',
        oldValues: null,
        newValues: jsonEncode(map),
        timestamp: DateTime.now().toIso8601String(),
        deviceId: deviceId,
      );
    });
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

  Future<void> updateInstrumentStatus(String instrumentId, String status, DateTime? clearedDate, {String deviceId = 'unknown_device'}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> oldRows = await db.query(
      'bank_instruments',
      where: 'id = ?',
      whereArgs: [instrumentId],
    );
    final oldMap = oldRows.isNotEmpty ? oldRows.first : null;
    final newValues = {
      'status': status,
      'cleared_date': clearedDate?.toIso8601String().substring(0, 10),
    };

    await db.transaction((txn) async {
      await txn.update(
        'bank_instruments',
        newValues,
        where: 'id = ?',
        whereArgs: [instrumentId],
      );

      await _dbHelper.insertAuditLog(
        txn,
        id: _uuid.v4(),
        tableName: 'bank_instruments',
        recordId: instrumentId,
        action: 'EDIT',
        oldValues: oldMap != null ? jsonEncode(oldMap) : null,
        newValues: jsonEncode(newValues),
        timestamp: DateTime.now().toIso8601String(),
        deviceId: deviceId,
      );
    });
  }

  // ─── Bank Reconciliation ───────────────────────────────────────────────────

  Future<void> insertBankReconciliation(BankReconciliation reconciliation, {String deviceId = 'unknown_device'}) async {
    final db = await _dbHelper.database;
    final map = reconciliation.toMap();
    await db.transaction((txn) async {
      await txn.insert('bank_reconciliation', map);

      await _dbHelper.insertAuditLog(
        txn,
        id: _uuid.v4(),
        tableName: 'bank_reconciliation',
        recordId: reconciliation.id,
        action: 'CREATE',
        oldValues: null,
        newValues: jsonEncode(map),
        timestamp: DateTime.now().toIso8601String(),
        deviceId: deviceId,
      );
    });
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
