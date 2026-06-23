import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../models/voucher.dart';
import '../models/voucher_line.dart';
import '../models/bill_allocation.dart';

class VoucherRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  // ─── Vouchers ──────────────────────────────────────────────────────────────

  Future<void> insertVoucher(Voucher voucher, List<VoucherLine> lines, {String deviceId = 'unknown_device'}) async {
    final db = await _dbHelper.database;
    final payload = {
      'voucher': voucher.toMap(),
      'lines': lines.map((l) => l.toMap()).toList(),
    };

    await db.transaction((txn) async {
      await txn.insert('vouchers', voucher.toMap());
      for (final line in lines) {
        await txn.insert('voucher_lines', line.toMap());
      }

      await _dbHelper.insertAuditLog(
        txn,
        id: _uuid.v4(),
        tableName: 'vouchers',
        recordId: voucher.id,
        action: 'CREATE',
        oldValues: null,
        newValues: jsonEncode(payload),
        timestamp: DateTime.now().toIso8601String(),
        deviceId: deviceId,
      );
    });
  }

  Future<void> updateVoucher(Voucher voucher, List<VoucherLine> lines, {String deviceId = 'unknown_device'}) async {
    final db = await _dbHelper.database;
    final oldVoucher = await getVoucherById(voucher.id);
    final oldLines = oldVoucher != null ? await getVoucherLines(voucher.id) : <VoucherLine>[];
    final oldPayload = oldVoucher != null ? {
      'voucher': oldVoucher.toMap(),
      'lines': oldLines.map((l) => l.toMap()).toList(),
    } : null;

    final newPayload = {
      'voucher': voucher.toMap(),
      'lines': lines.map((l) => l.toMap()).toList(),
    };

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

      await _dbHelper.insertAuditLog(
        txn,
        id: _uuid.v4(),
        tableName: 'vouchers',
        recordId: voucher.id,
        action: 'EDIT',
        oldValues: oldPayload != null ? jsonEncode(oldPayload) : null,
        newValues: jsonEncode(newPayload),
        timestamp: DateTime.now().toIso8601String(),
        deviceId: deviceId,
      );
    });
  }

  Future<void> deleteVoucher(String id, {String deviceId = 'unknown_device'}) async {
    final db = await _dbHelper.database;
    final oldVoucher = await getVoucherById(id);
    final oldLines = oldVoucher != null ? await getVoucherLines(id) : <VoucherLine>[];
    final oldPayload = oldVoucher != null ? {
      'voucher': oldVoucher.toMap(),
      'lines': oldLines.map((l) => l.toMap()).toList(),
    } : null;
    final newPayload = oldVoucher != null ? {
      'voucher': {
        ...oldVoucher.toMap(),
        'is_deleted': 1,
      },
      'lines': oldLines.map((l) => l.toMap()).toList(),
    } : null;

    await db.transaction((txn) async {
      await txn.update(
        'vouchers',
        {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

      await _dbHelper.insertAuditLog(
        txn,
        id: _uuid.v4(),
        tableName: 'vouchers',
        recordId: id,
        action: 'DELETE',
        oldValues: oldPayload != null ? jsonEncode(oldPayload) : null,
        newValues: newPayload != null ? jsonEncode(newPayload) : null,
        timestamp: DateTime.now().toIso8601String(),
        deviceId: deviceId,
      );
    });
  }

  Future<List<Voucher>> getVouchers({String? companyId, String? fyId, bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (companyId != null && fyId != null) {
      whereClause = activeOnly ? 'company_id = ? AND fy_id = ? AND is_deleted = 0 AND is_cancelled = 0' : 'company_id = ? AND fy_id = ?';
      whereArgs = [companyId, fyId];
    } else if (companyId != null) {
      whereClause = activeOnly ? 'company_id = ? AND is_deleted = 0 AND is_cancelled = 0' : 'company_id = ?';
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
      WHERE fts_vouchers MATCH ? AND v.company_id = ? AND v.is_deleted = 0 AND v.is_cancelled = 0
      ORDER BY v.date DESC, v.created_at DESC
    ''', ['$sanitizedQuery*', companyId]);
    return rows.map(Voucher.fromMap).toList();
  }
}
