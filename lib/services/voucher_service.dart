import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../data/database/db_helper.dart';
import '../data/models/voucher.dart';
import '../data/models/voucher_line.dart';
import '../data/models/stock_movement.dart';
import '../data/models/app_user.dart';
import '../core/utils/fy_guard.dart';

class VoucherDraft {
  final String? id;
  final String voucherNo;
  final String type;
  final DateTime date;
  final String? narration;
  final String companyId;
  final String fyId;
  final List<VoucherLineDraft> lines;
  final List<StockMovementDraft> inventoryMovements;

  VoucherDraft({
    this.id,
    required this.voucherNo,
    required this.type,
    required this.date,
    this.narration,
    required this.companyId,
    required this.fyId,
    required this.lines,
    this.inventoryMovements = const [],
  });
}

class VoucherLineDraft {
  final String? id;
  final String ledgerId;
  final double drAmount;
  final double crAmount;
  final String? narration;

  VoucherLineDraft({
    this.id,
    required this.ledgerId,
    this.drAmount = 0.0,
    this.crAmount = 0.0,
    this.narration,
  });
}

class StockMovementDraft {
  final String? id;
  final String stockItemId;
  final String godownId;
  final double qty;
  final double rate;
  final String movementType;
  final String? batchId;

  StockMovementDraft({
    this.id,
    required this.stockItemId,
    required this.godownId,
    required this.qty,
    required this.rate,
    required this.movementType,
    this.batchId,
  });
}

class VoucherService {
  static final VoucherService _instance = VoucherService._internal();
  factory VoucherService() => _instance;
  VoucherService._internal();

  final DbHelper _dbHelper = DbHelper();

  /// Posts a double-entry voucher with validation and logs under a single transaction.
  Future<Voucher> postVoucher(VoucherDraft draft, AppUser user, {String deviceId = 'local'}) async {
    // 1. Verify FY Lock Guard
    await FyGuard.checkDate(date: draft.date, companyId: draft.companyId, userRole: user.role);

    // 2. Validate double-entry balance: SUM(DR) == SUM(CR) with 1-paisa tolerance
    double drTotal = 0.0;
    double crTotal = 0.0;
    for (final line in draft.lines) {
      drTotal += line.drAmount;
      crTotal += line.crAmount;
    }
    if ((drTotal - crTotal).abs() > 0.01) {
      throw Exception('Voucher unbalanced: Total DR ($drTotal) must equal Total CR ($crTotal).');
    }

    final voucherId = draft.id ?? const Uuid().v4();
    final voucher = Voucher(
      id: voucherId,
      voucherNo: draft.voucherNo,
      type: draft.type,
      date: draft.date,
      narration: draft.narration,
      companyId: draft.companyId,
      fyId: draft.fyId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDeleted: false,
      isCancelled: false,
    );

    final lines = draft.lines.map((l) {
      return VoucherLine(
        id: l.id ?? const Uuid().v4(),
        voucherId: voucherId,
        ledgerId: l.ledgerId,
        drAmount: l.drAmount,
        crAmount: l.crAmount,
        narration: l.narration,
      );
    }).toList();

    final movements = draft.inventoryMovements.map((m) {
      return StockMovement(
        id: m.id ?? const Uuid().v4(),
        stockItemId: m.stockItemId,
        godownId: m.godownId,
        refVoucherId: voucherId,
        qty: m.qty,
        rate: m.rate,
        movementType: m.movementType,
        batchId: m.batchId,
        createdAt: DateTime.now(),
      );
    }).toList();

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('vouchers', voucher.toMap());
      for (final line in lines) {
        await txn.insert('voucher_lines', line.toMap());
      }
      for (final mvmt in movements) {
        await txn.insert('stock_movements', mvmt.toMap());
      }

      final payload = {
        'voucher': voucher.toMap(),
        'voucher_lines': lines.map((l) => l.toMap()).toList(),
        'bill_allocations': <Map<String, dynamic>>[],
        'stock_movements': movements.map((sm) => sm.toMap()).toList(),
        'bank_instruments': <Map<String, dynamic>>[],
      };

      // 3. Insert Audit Log
      await txn.insert('audit_logs', {
        'id': const Uuid().v4(),
        'table_name': 'vouchers',
        'record_id': voucher.id,
        'action': 'CREATE',
        'old_values': null,
        'new_values': jsonEncode(payload),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // 4. Insert Sync Queue record
      await txn.insert('sync_queue', {
        'id': const Uuid().v4(),
        'operation': 'CREATE',
        'table_name': 'vouchers',
        'record_id': voucher.id,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });

    return voucher;
  }

  /// Cancels a voucher, reversing ledger entries and inventory movements.
  Future<void> cancelVoucher(String voucherId, AppUser user, {String deviceId = 'local'}) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final List<Map<String, dynamic>> voucherRows = await txn.query(
        'vouchers',
        where: 'id = ?',
        whereArgs: [voucherId],
      );
      if (voucherRows.isEmpty) {
        throw Exception('Voucher not found');
      }
      final oldVoucher = Voucher.fromMap(voucherRows.first);

      // Verify FY lock guard
      await FyGuard.checkDate(date: oldVoucher.date, companyId: oldVoucher.companyId, userRole: user.role);

      final List<Map<String, dynamic>> lineRows = await txn.query(
        'voucher_lines',
        where: 'voucher_id = ?',
        whereArgs: [voucherId],
      );
      final List<Map<String, dynamic>> movementRows = await txn.query(
        'stock_movements',
        where: 'ref_voucher_id = ?',
        whereArgs: [voucherId],
      );

      final oldPayload = {
        'voucher': oldVoucher.toMap(),
        'voucher_lines': lineRows,
        'bill_allocations': <Map<String, dynamic>>[],
        'stock_movements': movementRows,
        'bank_instruments': <Map<String, dynamic>>[],
      };

      await txn.update(
        'vouchers',
        {'is_cancelled': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [voucherId],
      );

      await txn.delete(
        'stock_movements',
        where: 'ref_voucher_id = ?',
        whereArgs: [voucherId],
      );

      final newVoucherMap = Map<String, dynamic>.from(oldVoucher.toMap());
      newVoucherMap['is_cancelled'] = 1;
      newVoucherMap['updated_at'] = DateTime.now().toIso8601String();

      final newPayload = {
        'voucher': newVoucherMap,
        'voucher_lines': lineRows,
        'bill_allocations': <Map<String, dynamic>>[],
        'stock_movements': <Map<String, dynamic>>[],
        'bank_instruments': <Map<String, dynamic>>[],
      };

      await txn.insert('audit_logs', {
        'id': const Uuid().v4(),
        'table_name': 'vouchers',
        'record_id': voucherId,
        'action': 'EDIT',
        'old_values': jsonEncode(oldPayload),
        'new_values': jsonEncode(newPayload),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      await txn.insert('sync_queue', {
        'id': const Uuid().v4(),
        'operation': 'EDIT',
        'table_name': 'vouchers',
        'record_id': voucherId,
        'payload': jsonEncode(newPayload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Soft deletes a voucher, reversing inventory and ledger balances.
  Future<void> deleteVoucher(String voucherId, AppUser user, {String deviceId = 'local'}) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final List<Map<String, dynamic>> voucherRows = await txn.query(
        'vouchers',
        where: 'id = ?',
        whereArgs: [voucherId],
      );
      if (voucherRows.isEmpty) {
        throw Exception('Voucher not found');
      }
      final oldVoucher = Voucher.fromMap(voucherRows.first);

      // Verify FY lock guard
      await FyGuard.checkDate(date: oldVoucher.date, companyId: oldVoucher.companyId, userRole: user.role);

      final List<Map<String, dynamic>> lineRows = await txn.query(
        'voucher_lines',
        where: 'voucher_id = ?',
        whereArgs: [voucherId],
      );
      final List<Map<String, dynamic>> movementRows = await txn.query(
        'stock_movements',
        where: 'ref_voucher_id = ?',
        whereArgs: [voucherId],
      );

      final oldPayload = {
        'voucher': oldVoucher.toMap(),
        'voucher_lines': lineRows,
        'bill_allocations': <Map<String, dynamic>>[],
        'stock_movements': movementRows,
        'bank_instruments': <Map<String, dynamic>>[],
      };

      await txn.update(
        'vouchers',
        {'is_deleted': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [voucherId],
      );

      await txn.delete(
        'stock_movements',
        where: 'ref_voucher_id = ?',
        whereArgs: [voucherId],
      );

      final newVoucherMap = Map<String, dynamic>.from(oldVoucher.toMap());
      newVoucherMap['is_deleted'] = 1;
      newVoucherMap['updated_at'] = DateTime.now().toIso8601String();

      final newPayload = {
        'voucher': newVoucherMap,
        'voucher_lines': lineRows,
        'bill_allocations': <Map<String, dynamic>>[],
        'stock_movements': <Map<String, dynamic>>[],
        'bank_instruments': <Map<String, dynamic>>[],
      };

      await txn.insert('audit_logs', {
        'id': const Uuid().v4(),
        'table_name': 'vouchers',
        'record_id': voucherId,
        'action': 'DELETE',
        'old_values': jsonEncode(oldPayload),
        'new_values': jsonEncode(newPayload),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      await txn.insert('sync_queue', {
        'id': const Uuid().v4(),
        'operation': 'DELETE',
        'table_name': 'vouchers',
        'record_id': voucherId,
        'payload': jsonEncode(newPayload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Alters a voucher by cancelling the old one and posting the modified one inside a transaction.
  Future<Voucher> alterVoucher(String oldVoucherId, VoucherDraft draft, AppUser user, {String deviceId = 'local'}) async {
    final db = await _dbHelper.database;
    Voucher? newVoucher;
    await db.transaction((txn) async {
      final List<Map<String, dynamic>> voucherRows = await txn.query(
        'vouchers',
        where: 'id = ?',
        whereArgs: [oldVoucherId],
      );
      if (voucherRows.isEmpty) {
        throw Exception('Voucher to alter not found');
      }
      final oldVoucher = Voucher.fromMap(voucherRows.first);

      // Verify FY lock guard
      await FyGuard.checkDate(date: oldVoucher.date, companyId: oldVoucher.companyId, userRole: user.role);

      final List<Map<String, dynamic>> lineRows = await txn.query(
        'voucher_lines',
        where: 'voucher_id = ?',
        whereArgs: [oldVoucherId],
      );
      final List<Map<String, dynamic>> movementRows = await txn.query(
        'stock_movements',
        where: 'ref_voucher_id = ?',
        whereArgs: [oldVoucherId],
      );

      final oldPayload = {
        'voucher': oldVoucher.toMap(),
        'voucher_lines': lineRows,
        'bill_allocations': <Map<String, dynamic>>[],
        'stock_movements': movementRows,
        'bank_instruments': <Map<String, dynamic>>[],
      };

      // 1. Cancel the old voucher
      await txn.update(
        'vouchers',
        {'is_cancelled': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [oldVoucherId],
      );

      await txn.delete(
        'stock_movements',
        where: 'ref_voucher_id = ?',
        whereArgs: [oldVoucherId],
      );

      final oldCancelledVoucherMap = Map<String, dynamic>.from(oldVoucher.toMap());
      oldCancelledVoucherMap['is_cancelled'] = 1;
      oldCancelledVoucherMap['updated_at'] = DateTime.now().toIso8601String();

      final oldCancelledPayload = {
        'voucher': oldCancelledVoucherMap,
        'voucher_lines': lineRows,
        'bill_allocations': <Map<String, dynamic>>[],
        'stock_movements': <Map<String, dynamic>>[],
        'bank_instruments': <Map<String, dynamic>>[],
      };

      await txn.insert('audit_logs', {
        'id': const Uuid().v4(),
        'table_name': 'vouchers',
        'record_id': oldVoucherId,
        'action': 'EDIT',
        'old_values': jsonEncode(oldPayload),
        'new_values': jsonEncode(oldCancelledPayload),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      await txn.insert('sync_queue', {
        'id': const Uuid().v4(),
        'operation': 'EDIT',
        'table_name': 'vouchers',
        'record_id': oldVoucherId,
        'payload': jsonEncode(oldCancelledPayload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });

      // 2. Post the modified draft
      final newVoucherId = draft.id ?? const Uuid().v4();
      newVoucher = Voucher(
        id: newVoucherId,
        voucherNo: draft.voucherNo,
        type: draft.type,
        date: draft.date,
        narration: draft.narration,
        companyId: draft.companyId,
        fyId: draft.fyId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDeleted: false,
        isCancelled: false,
      );

      final newLines = draft.lines.map((l) {
        return VoucherLine(
          id: l.id ?? const Uuid().v4(),
          voucherId: newVoucherId,
          ledgerId: l.ledgerId,
          drAmount: l.drAmount,
          crAmount: l.crAmount,
          narration: l.narration,
        );
      }).toList();

      final newMovements = draft.inventoryMovements.map((m) {
        return StockMovement(
          id: m.id ?? const Uuid().v4(),
          stockItemId: m.stockItemId,
          godownId: m.godownId,
          refVoucherId: newVoucherId,
          qty: m.qty,
          rate: m.rate,
          movementType: m.movementType,
          batchId: m.batchId,
          createdAt: DateTime.now(),
        );
      }).toList();

      await txn.insert('vouchers', newVoucher!.toMap());
      for (final line in newLines) {
        await txn.insert('voucher_lines', line.toMap());
      }
      for (final mvmt in newMovements) {
        await txn.insert('stock_movements', mvmt.toMap());
      }

      final newPayload = {
        'voucher': newVoucher!.toMap(),
        'voucher_lines': newLines.map((l) => l.toMap()).toList(),
        'bill_allocations': <Map<String, dynamic>>[],
        'stock_movements': newMovements.map((sm) => sm.toMap()).toList(),
        'bank_instruments': <Map<String, dynamic>>[],
      };

      await txn.insert('audit_logs', {
        'id': const Uuid().v4(),
        'table_name': 'vouchers',
        'record_id': newVoucherId,
        'action': 'CREATE',
        'old_values': null,
        'new_values': jsonEncode(newPayload),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      await txn.insert('sync_queue', {
        'id': const Uuid().v4(),
        'operation': 'CREATE',
        'table_name': 'vouchers',
        'record_id': newVoucherId,
        'payload': jsonEncode(newPayload),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });

    return newVoucher!;
  }
}
