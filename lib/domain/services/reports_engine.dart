import '../../data/database/db_helper.dart';
import '../../data/models/stock_movement.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../data/repositories/brs_repository.dart';

class LedgerBalance {
  final String ledgerId;
  final String name;
  final String groupName;
  final String groupNature;
  final double openingBalance;
  final String balanceType;
  final double drTotal;
  final double crTotal;
  final double closingBalance;

  LedgerBalance({
    required this.ledgerId,
    required this.name,
    required this.groupName,
    required this.groupNature,
    required this.openingBalance,
    required this.balanceType,
    required this.drTotal,
    required this.crTotal,
    required this.closingBalance,
  });
}

class ReportsEngine {
  final LedgerRepository _ledgerRepo = LedgerRepository();
  final BrsRepository _brsRepo = BrsRepository();
  final DbHelper _dbHelper = DbHelper();

  // ─── Trial Balance ─────────────────────────────────────────────────────────

  Future<List<LedgerBalance>> getTrialBalance(String companyId, String fyId) async {
    final db = await _dbHelper.database;

    // 1. Fetch ledgers and groups
    final ledgers = await _ledgerRepo.getLedgers(companyId: companyId, activeOnly: false);
    final groups = await _ledgerRepo.getLedgerGroups();
    final groupMap = {for (var g in groups) g.id: g};

    // 2. Fetch voucher line aggregates for DR / CR
    final lineAggs = await db.rawQuery('''
      SELECT vl.ledger_id, SUM(vl.dr_amount) as total_dr, SUM(vl.cr_amount) as total_cr
      FROM voucher_lines vl
      JOIN vouchers v ON vl.voucher_id = v.id
      WHERE v.company_id = ? AND v.fy_id = ? AND v.is_deleted = 0 AND v.is_cancelled = 0
      GROUP BY vl.ledger_id
    ''', [companyId, fyId]);

    final aggMap = {
      for (var row in lineAggs)
        row['ledger_id'] as String: {
          'dr': (row['total_dr'] as num?)?.toDouble() ?? 0.0,
          'cr': (row['total_cr'] as num?)?.toDouble() ?? 0.0,
        }
    };

    final List<LedgerBalance> balances = [];
    for (final ledger in ledgers) {
      final group = groupMap[ledger.groupId];
      final groupName = group?.name ?? 'UNKNOWN';
      final groupNature = group?.nature ?? 'ASSETS';

      final agg = aggMap[ledger.id] ?? {'dr': 0.0, 'cr': 0.0};
      final drTotal = agg['dr']!;
      final crTotal = agg['cr']!;

      // Calculate closing balance
      double closing = ledger.openingBalance;
      if (ledger.balanceType == 'DR') {
        closing = closing + drTotal - crTotal;
      } else {
        closing = closing + crTotal - drTotal;
      }

      balances.add(LedgerBalance(
        ledgerId: ledger.id,
        name: ledger.name,
        groupName: groupName,
        groupNature: groupNature,
        openingBalance: ledger.openingBalance,
        balanceType: ledger.balanceType,
        drTotal: drTotal,
        crTotal: crTotal,
        closingBalance: closing,
      ));
    }

    return balances;
  }

  // ─── Profit & Loss (P&L) ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> getProfitLoss(String companyId, String fyId) async {
    final balances = await getTrialBalance(companyId, fyId);

    double totalIncome = 0.0;
    double totalExpenses = 0.0;
    final List<LedgerBalance> incomes = [];
    final List<LedgerBalance> expenses = [];

    for (final bal in balances) {
      if (bal.groupNature == 'INCOME') {
        incomes.add(bal);
        // Income is normally CR
        totalIncome += bal.balanceType == 'CR' ? bal.closingBalance : -bal.closingBalance;
      } else if (bal.groupNature == 'EXPENSES') {
        expenses.add(bal);
        // Expense is normally DR
        totalExpenses += bal.balanceType == 'DR' ? bal.closingBalance : -bal.closingBalance;
      }
    }

    final netProfit = totalIncome - totalExpenses;

    return {
      'incomes': incomes,
      'expenses': expenses,
      'total_income': totalIncome,
      'total_expenses': totalExpenses,
      'net_profit': netProfit,
    };
  }

  // ─── Balance Sheet ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getBalanceSheet(String companyId, String fyId) async {
    final balances = await getTrialBalance(companyId, fyId);
    final pl = await getProfitLoss(companyId, fyId);
    final double netProfit = pl['net_profit'] as double;

    double totalAssets = 0.0;
    double totalLiabilities = 0.0;
    final List<LedgerBalance> assets = [];
    final List<LedgerBalance> liabilities = [];

    for (final bal in balances) {
      if (bal.groupNature == 'ASSETS') {
        assets.add(bal);
        // Assets are normally DR
        totalAssets += bal.balanceType == 'DR' ? bal.closingBalance : -bal.closingBalance;
      } else if (bal.groupNature == 'LIABILITIES') {
        liabilities.add(bal);
        // Liabilities are normally CR
        totalLiabilities += bal.balanceType == 'CR' ? bal.closingBalance : -bal.closingBalance;
      }
    }

    // Retained earnings / Net Profit added to Liabilities/Equity side
    final totalLiabilitiesAndEquity = totalLiabilities + netProfit;
    final difference = (totalAssets - totalLiabilitiesAndEquity).abs();

    return {
      'assets': assets,
      'liabilities': liabilities,
      'total_assets': totalAssets,
      'total_liabilities': totalLiabilities,
      'net_profit': netProfit,
      'total_liabilities_and_equity': totalLiabilitiesAndEquity,
      'difference': difference,
    };
  }

  // ─── FIFO Costing Valuation ────────────────────────────────────────────────

  double calculateFIFOCosting(List<StockMovement> movements) {
    // List to queue purchases: stores [qty, rate]
    final List<List<double>> purchaseQueue = [];

    for (final movement in movements) {
      if (movement.movementType == 'IN') {
        purchaseQueue.add([movement.qty, movement.rate]);
      } else {
        // Consumer OUT movement
        double qtyToConsume = movement.qty;
        while (qtyToConsume > 0 && purchaseQueue.isNotEmpty) {
          final first = purchaseQueue.first;
          final availableQty = first[0];
          if (availableQty <= qtyToConsume) {
            qtyToConsume -= availableQty;
            purchaseQueue.removeAt(0);
          } else {
            first[0] = availableQty - qtyToConsume;
            qtyToConsume = 0;
          }
        }
      }
    }

    // Value remaining inventory in queue
    double totalValuation = 0.0;
    for (final item in purchaseQueue) {
      totalValuation += item[0] * item[1];
    }
    return totalValuation;
  }

  // ─── Bank Reconciliation (BRS) ─────────────────────────────────────────────

  Future<Map<String, dynamic>> getBRS(String bankLedgerId) async {
    final db = await _dbHelper.database;

    // 1. Calculate Book Balance
    final bookRow = await db.rawQuery('''
      SELECT SUM(vl.dr_amount) as total_dr, SUM(vl.cr_amount) as total_cr
      FROM voucher_lines vl
      JOIN vouchers v ON vl.voucher_id = v.id
      WHERE vl.ledger_id = ? AND v.is_deleted = 0 AND v.is_cancelled = 0
    ''', [bankLedgerId]);

    final drTotal = (bookRow.first['total_dr'] as num?)?.toDouble() ?? 0.0;
    final crTotal = (bookRow.first['total_cr'] as num?)?.toDouble() ?? 0.0;
    final bookBalance = drTotal - crTotal; // Bank ledger is Asset (Normally DR)

    // 2. Fetch uncleared bank instruments
    final uncleared = await _brsRepo.getUnclearedInstruments(bankLedgerId);

    // Sum uncleared
    double unclearedDeposits = 0.0;  // Receipt instruments
    double unclearedPayments = 0.0;  // Payment instruments

    final List<Map<String, dynamic>> instrumentsList = [];
    for (final row in uncleared) {
      final amount = (row['amount'] as num).toDouble();
      final status = row['status'] as String;

      if (status == 'RECEIVED' || status == 'PENDING') {
        unclearedDeposits += amount;
      } else if (status == 'ISSUED') {
        unclearedPayments += amount;
      }

      instrumentsList.add(row);
    }

    // Reconciled balance (Bank statement balance should equal this when reconciled)
    // Reconciled = Book Balance + Uncleared Payments (Cheques issued but not cleared) - Uncleared Deposits (Cheques received but not cleared)
    final reconciledBalance = bookBalance + unclearedPayments - unclearedDeposits;

    final latestReconciliation = await _brsRepo.getLatestReconciliation(bankLedgerId);

    return {
      'book_balance': bookBalance,
      'uncleared_payments': unclearedPayments,
      'uncleared_deposits': unclearedDeposits,
      'reconciled_balance': reconciledBalance,
      'instruments': instrumentsList,
      'latest_reconciliation': latestReconciliation,
    };
  }

  /// Fetches double-entry vouchers with their ledger postings (debits/credits) for the Day Book report
  Future<List<Map<String, dynamic>>> getDoubleEntryDayBook(String companyId, String fyId, {DateTime? startDate, DateTime? endDate}) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'v.company_id = ? AND v.fy_id = ? AND v.is_deleted = 0';
    List<dynamic> whereArgs = [companyId, fyId];
    
    if (startDate != null) {
      whereClause += ' AND v.date >= ?';
      whereArgs.add(startDate.toIso8601String().substring(0, 10));
    }
    if (endDate != null) {
      whereClause += ' AND v.date <= ?';
      whereArgs.add(endDate.toIso8601String().substring(0, 10));
    }
    
    final List<Map<String, dynamic>> voucherRows = await db.rawQuery('''
      SELECT v.id, v.voucher_no, v.type, v.date, v.narration
      FROM vouchers v
      WHERE $whereClause
      ORDER BY v.date DESC, v.created_at DESC
    ''', whereArgs);
    
    final List<Map<String, dynamic>> result = [];
    
    for (final vRow in voucherRows) {
      final String voucherId = vRow['id'] as String;
      
      final List<Map<String, dynamic>> lineRows = await db.rawQuery('''
        SELECT l.name as ledger_name, vl.dr_amount, vl.cr_amount, vl.narration
        FROM voucher_lines vl
        JOIN ledgers l ON vl.ledger_id = l.id
        WHERE vl.voucher_id = ?
      ''', [voucherId]);
      
      result.add({
        'id': voucherId,
        'voucher_no': vRow['voucher_no'],
        'type': vRow['type'],
        'date': DateTime.parse(vRow['date'] as String),
        'narration': vRow['narration'],
        'lines': lineRows.map((row) => {
          'ledger_name': row['ledger_name'],
          'dr_amount': (row['dr_amount'] as num).toDouble(),
          'cr_amount': (row['cr_amount'] as num).toDouble(),
          'narration': row['narration'],
        }).toList(),
      });
    }
    
    return result;
  }
}
