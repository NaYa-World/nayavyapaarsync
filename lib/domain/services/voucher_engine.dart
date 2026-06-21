import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../core/utils/fy_guard.dart';
import '../../data/models/ledger_group.dart';
import '../../data/models/voucher.dart';
import '../../data/models/voucher_line.dart';
import '../../data/models/stock_movement.dart';
import '../../data/models/bank_instrument.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../data/database/db_helper.dart';

class VoucherUnbalancedException implements Exception {
  final double drTotal;
  final double crTotal;
  VoucherUnbalancedException(this.drTotal, this.crTotal);
  @override
  String toString() => 'Voucher unbalanced: Total DR ($drTotal) must equal Total CR ($crTotal).';
}

class InvalidContraVoucherException implements Exception {
  final String message;
  InvalidContraVoucherException(this.message);
  @override
  String toString() => message;
}

class VoucherEngine {
  final LedgerRepository _ledgerRepo = LedgerRepository();
  final DbHelper _dbHelper = DbHelper();

  /// Posts a double-entry voucher with business validations inside a transaction.
  Future<void> postVoucher({
    required Voucher voucher,
    required List<VoucherLine> lines,
    List<StockMovement>? stockMovements,
    List<BankInstrument>? bankInstruments,
    String? userRole,
    String deviceId = 'local',
  }) async {
    // 1. Verify FY Lock Guard
    await FyGuard.checkDate(date: voucher.date, companyId: voucher.companyId, userRole: userRole);

    // 2. Validate double-entry balance: SUM(DR) == SUM(CR)
    double drTotal = 0.0;
    double crTotal = 0.0;
    for (final line in lines) {
      drTotal += line.drAmount;
      crTotal += line.crAmount;
    }
    // Float comparison safety: check diff within 0.001
    if ((drTotal - crTotal).abs() > 0.001) {
      throw VoucherUnbalancedException(drTotal, crTotal);
    }

    // 3. Validate Contra restrictions
    if (voucher.type == 'CONTRA') {
      for (final line in lines) {
        final isCashOrBank = await _isCashOrBankLedger(line.ledgerId);
        if (!isCashOrBank) {
          throw InvalidContraVoucherException(
            'Contra voucher error: Ledger (${line.ledgerId}) is not a Cash or Bank account.'
          );
        }
      }
    }

    // 4. Save to Database inside a single SQL transaction
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // Create voucher header
      await txn.insert('vouchers', voucher.toMap());

      // Create lines
      for (final line in lines) {
        await txn.insert('voucher_lines', line.toMap());
      }

      // Create stock movements (if purchase/sale/credit_note/debit_note inventory)
      if (stockMovements != null) {
        for (final movement in stockMovements) {
          await txn.insert('stock_movements', movement.toMap());
        }
      }

      // Create bank instruments (cheques/DDs/NEFTs for payments/receipts)
      if (bankInstruments != null) {
        for (final instrument in bankInstruments) {
          await txn.insert('bank_instruments', instrument.toMap());
        }
      }

      final payload = {
        'voucher': voucher.toMap(),
        'voucher_lines': lines.map((l) => l.toMap()).toList(),
        'bill_allocations': <Map<String, dynamic>>[],
        'stock_movements': stockMovements?.map((sm) => sm.toMap()).toList() ?? [],
        'bank_instruments': bankInstruments?.map((bi) => bi.toMap()).toList() ?? [],
      };

      // 5. Insert Audit Log
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

      // 6. Insert Sync Queue record
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
  }

  /// Traverses group hierarchy to determine if ledger is Cash or Bank.
  Future<bool> _isCashOrBankLedger(String ledgerId) async {
    final ledger = await _ledgerRepo.getLedgerById(ledgerId);
    if (ledger == null) return false;
    final groups = await _ledgerRepo.getLedgerGroups();

    String? currentGroupId = ledger.groupId;
    while (currentGroupId != null) {
      final grp = groups.firstWhere(
        (g) => g.id == currentGroupId,
        orElse: () => LedgerGroup(id: '', name: 'UNKNOWN', nature: 'ASSETS'),
      );
      if (grp.id.isEmpty) break;

      // Ensure root group nature is ASSETS to avoid matching expense/income containing "cash"/"bank"
      if (grp.nature == 'ASSETS') {
        final nameUpper = grp.name.toUpperCase();
        if (nameUpper.contains('CASH') || nameUpper.contains('BANK')) {
          return true;
        }
      }
      currentGroupId = grp.parentId;
    }
    return false;
  }
}
