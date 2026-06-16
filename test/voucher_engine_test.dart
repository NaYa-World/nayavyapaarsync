import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:godown_management/data/database/db_helper.dart';
import 'package:godown_management/data/models/ledger_group.dart';
import 'package:godown_management/data/models/ledger.dart';
import 'package:godown_management/data/models/voucher.dart';
import 'package:godown_management/data/models/voucher_line.dart';
import 'package:godown_management/data/models/stock_movement.dart';
import 'package:godown_management/data/models/bank_instrument.dart';
import 'package:godown_management/data/repositories/ledger_repository.dart';
import 'package:godown_management/data/repositories/brs_repository.dart';
import 'package:godown_management/domain/services/voucher_engine.dart';
import 'package:godown_management/domain/services/reports_engine.dart';
import 'package:godown_management/core/utils/fy_guard.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('VoucherEngine and ReportsEngine Double-Entry Tests', () {
    late DbHelper dbHelper;
    late LedgerRepository ledgerRepo;
    late BrsRepository brsRepo;
    late VoucherEngine voucherEngine;
    late ReportsEngine reportsEngine;

    setUp(() async {
      dbHelper = DbHelper();
      ledgerRepo = LedgerRepository();
      brsRepo = BrsRepository();
      voucherEngine = VoucherEngine();
      reportsEngine = ReportsEngine();

      await dbHelper.close();
      final databasePath = await getDatabasesPath();
      final path = '$databasePath/godown_management.db';
      try {
        await deleteDatabase(path);
      } catch (_) {}

      // Pre-seed mock company and financial year
      final db = await dbHelper.database;
      await db.insert('companies', {
        'id': 'comp_test',
        'name': 'Vedic Agro Seeds',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      await db.insert('financial_years', {
        'id': 'fy_test',
        'company_id': 'comp_test',
        'label': 'FY 26-27',
        'start_date': '2026-04-01',
        'end_date': '2027-03-31',
        'is_locked': 0,
      });

      // Pre-seed basic ledger groups
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_assets', name: 'Current Assets', nature: 'ASSETS'));
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_cash', name: 'Cash-in-hand', parentId: 'grp_assets', nature: 'ASSETS'));
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_bank', name: 'Bank Accounts', parentId: 'grp_assets', nature: 'ASSETS'));
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_liabilities', name: 'Current Liabilities', nature: 'LIABILITIES'));
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_income', name: 'Sales Accounts', nature: 'INCOME'));
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_expenses', name: 'Purchase Accounts', nature: 'EXPENSES'));

      // Pre-seed basic ledgers
      await ledgerRepo.createLedger(Ledger(id: 'led_cash', name: 'Cash Account', groupId: 'grp_cash', balanceType: 'DR', companyId: 'comp_test', createdAt: DateTime.now()));
      await ledgerRepo.createLedger(Ledger(id: 'led_sbi', name: 'SBI Bank Account', groupId: 'grp_bank', balanceType: 'DR', companyId: 'comp_test', createdAt: DateTime.now()));
      await ledgerRepo.createLedger(Ledger(id: 'led_sales', name: 'Product Sales', groupId: 'grp_income', balanceType: 'CR', companyId: 'comp_test', createdAt: DateTime.now()));
      await ledgerRepo.createLedger(Ledger(id: 'led_purchases', name: 'Product Purchases', groupId: 'grp_expenses', balanceType: 'DR', companyId: 'comp_test', createdAt: DateTime.now()));
      await ledgerRepo.createLedger(Ledger(id: 'led_supplier', name: 'Supplier Ledger', groupId: 'grp_liabilities', balanceType: 'CR', companyId: 'comp_test', createdAt: DateTime.now()));
    });

    tearDown(() async {
      await dbHelper.close();
    });

    test('VoucherEngine blocks unbalanced entries', () async {
      final v = Voucher(
        id: 'vch-1',
        voucherNo: 'VCH/001',
        type: 'SALE',
        date: DateTime(2026, 6, 15),
        companyId: 'comp_test',
        fyId: 'fy_test',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final lines = [
        VoucherLine(id: 'vl-1', voucherId: 'vch-1', ledgerId: 'led_cash', drAmount: 1500.0),
        VoucherLine(id: 'vl-2', voucherId: 'vch-1', ledgerId: 'led_sales', crAmount: 1200.0), // unbalanced
      ];

      expect(
        () => voucherEngine.postVoucher(voucher: v, lines: lines),
        throwsA(isA<VoucherUnbalancedException>()),
      );
    });

    test('VoucherEngine enforces Contra restrictions', () async {
      final v = Voucher(
        id: 'vch-2',
        voucherNo: 'CON/001',
        type: 'CONTRA',
        date: DateTime(2026, 6, 15),
        companyId: 'comp_test',
        fyId: 'fy_test',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Invalid Contra: Cash Account (Valid) -> Product Sales (Invalid: INCOME group)
      final lines = [
        VoucherLine(id: 'vl-3', voucherId: 'vch-2', ledgerId: 'led_cash', drAmount: 500.0),
        VoucherLine(id: 'vl-4', voucherId: 'vch-2', ledgerId: 'led_sales', crAmount: 500.0),
      ];

      expect(
        () => voucherEngine.postVoucher(voucher: v, lines: lines),
        throwsA(isA<InvalidContraVoucherException>()),
      );

      // Valid Contra: Cash Account (Valid) -> SBI Bank Account (Valid)
      final validLines = [
        VoucherLine(id: 'vl-5', voucherId: 'vch-2', ledgerId: 'led_sbi', drAmount: 1000.0),
        VoucherLine(id: 'vl-6', voucherId: 'vch-2', ledgerId: 'led_cash', crAmount: 1000.0),
      ];

      await voucherEngine.postVoucher(voucher: v, lines: validLines);
    });

    test('VoucherEngine honors FY locks and CA/Admin bypasses', () async {
      // Lock the Financial Year
      final db = await dbHelper.database;
      await db.update('financial_years', {'is_locked': 1}, where: 'id = ?', whereArgs: ['fy_test']);

      final v = Voucher(
        id: 'vch-locked',
        voucherNo: 'VCH/002',
        type: 'SALE',
        date: DateTime(2026, 6, 15),
        companyId: 'comp_test',
        fyId: 'fy_test',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final lines = [
        VoucherLine(id: 'vl-7', voucherId: 'vch-locked', ledgerId: 'led_cash', drAmount: 500.0),
        VoucherLine(id: 'vl-8', voucherId: 'vch-locked', ledgerId: 'led_sales', crAmount: 500.0),
      ];

      // Rejects standard user (unspecified role)
      expect(
        () => voucherEngine.postVoucher(voucher: v, lines: lines),
        throwsA(isA<LockedPeriodException>()),
      );

      // Rejects ACCOUNTANT role
      expect(
        () => voucherEngine.postVoucher(voucher: v, lines: lines, userRole: 'ACCOUNTANT'),
        throwsA(isA<LockedPeriodException>()),
      );

      // Bypasses for CA or ADMIN roles
      await voucherEngine.postVoucher(voucher: v, lines: lines, userRole: 'CA');
    });

    test('FIFO stock costing calculation', () {
      final itemMovements = [
        StockMovement(id: 'm-1', stockItemId: 'item-1', godownId: 'g-1', refVoucherId: 'v-1', qty: 100.0, rate: 5.0, movementType: 'IN', createdAt: DateTime(2026, 4, 1)),
        StockMovement(id: 'm-2', stockItemId: 'item-1', godownId: 'g-1', refVoucherId: 'v-2', qty: 50.0, rate: 6.0, movementType: 'IN', createdAt: DateTime(2026, 4, 5)),
        StockMovement(id: 'm-3', stockItemId: 'item-1', godownId: 'g-1', refVoucherId: 'v-3', qty: 120.0, rate: 5.5, movementType: 'OUT', createdAt: DateTime(2026, 4, 10)), // consumes 100 @ 5.0, 20 @ 6.0
      ];

      final closingValuation = reportsEngine.calculateFIFOCosting(itemMovements);
      // Remaining: 30 items @ 6.0 = 180.0
      expect(closingValuation, 180.0);
    });

    test('BRS calculation and bank instruments clearing', () async {
      final v = Voucher(
        id: 'vch-pay',
        voucherNo: 'PAY/001',
        type: 'PAYMENT',
        date: DateTime(2026, 6, 15),
        companyId: 'comp_test',
        fyId: 'fy_test',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final lines = [
        VoucherLine(id: 'vl-9', voucherId: 'vch-pay', ledgerId: 'led_supplier', drAmount: 5000.0),
        VoucherLine(id: 'vl-10', voucherId: 'vch-pay', ledgerId: 'led_sbi', crAmount: 5000.0), // Cr Bank
      ];

      final instrument = BankInstrument(
        id: 'chq-1',
        voucherId: 'vch-pay',
        instrumentType: 'CHEQUE',
        instrumentNo: 'CHQ-009988',
        bankName: 'SBI',
        amount: 5000.0,
        status: 'ISSUED',
      );

      // Post payment voucher
      await voucherEngine.postVoucher(
        voucher: v,
        lines: lines,
        bankInstruments: [instrument],
      );

      // 1. Check book balance (should be -5000.0 CR) and reconciled balance (should be 0.0 because cheque is uncleared)
      var brs = await reportsEngine.getBRS('led_sbi');
      expect(brs['book_balance'], -5000.0);
      expect(brs['reconciled_balance'], 0.0); // Book balance + uncleared payment (-5000 + 5000)
      expect(brs['instruments'].length, 1);

      // 2. Clear instrument
      await brsRepo.updateInstrumentStatus('chq-1', 'CLEARED', DateTime(2026, 6, 18));

      // 3. Check BRS again: reconciled balance should now equal book balance (-5000.0)
      brs = await reportsEngine.getBRS('led_sbi');
      expect(brs['book_balance'], -5000.0);
      expect(brs['reconciled_balance'], -5000.0); // No uncleared payments left
      expect(brs['instruments'].length, 0); // No uncleared instruments
    });

    test('ReportsEngine Trial Balance and Profit/Loss matching', () async {
      // 1. Post Sale Voucher (Products Sales Cr 3000, Cash Dr 3000)
      final v1 = Voucher(id: 'v-sale-1', voucherNo: 'SAL/001', type: 'SALE', date: DateTime(2026, 5, 1), companyId: 'comp_test', fyId: 'fy_test', createdAt: DateTime.now(), updatedAt: DateTime.now());
      final lines1 = [
        VoucherLine(id: 'vl-11', voucherId: 'v-sale-1', ledgerId: 'led_cash', drAmount: 3000.0),
        VoucherLine(id: 'vl-12', voucherId: 'v-sale-1', ledgerId: 'led_sales', crAmount: 3000.0),
      ];
      await voucherEngine.postVoucher(voucher: v1, lines: lines1);

      // 2. Post Purchase Voucher (Product Purchases Dr 1200, Supplier Cr 1200)
      final v2 = Voucher(id: 'v-pur-1', voucherNo: 'PUR/001', type: 'PURCHASE', date: DateTime(2026, 5, 5), companyId: 'comp_test', fyId: 'fy_test', createdAt: DateTime.now(), updatedAt: DateTime.now());
      final lines2 = [
        VoucherLine(id: 'vl-13', voucherId: 'v-pur-1', ledgerId: 'led_purchases', drAmount: 1200.0),
        VoucherLine(id: 'vl-14', voucherId: 'v-pur-1', ledgerId: 'led_supplier', crAmount: 1200.0),
      ];
      await voucherEngine.postVoucher(voucher: v2, lines: lines2);

      // 3. Verify Trial Balance
      final tb = await reportsEngine.getTrialBalance('comp_test', 'fy_test');
      expect(tb.length, 5);

      final cashBal = tb.firstWhere((b) => b.ledgerId == 'led_cash');
      expect(cashBal.closingBalance, 3000.0);
      expect(cashBal.balanceType, 'DR');

      final salesBal = tb.firstWhere((b) => b.ledgerId == 'led_sales');
      expect(salesBal.closingBalance, 3000.0);
      expect(salesBal.balanceType, 'CR');

      // 4. Verify P&L: Income (3000) - Expense (1200) = Net Profit (1800)
      final pl = await reportsEngine.getProfitLoss('comp_test', 'fy_test');
      expect(pl['total_income'], 3000.0);
      expect(pl['total_expenses'], 1200.0);
      expect(pl['net_profit'], 1800.0);

      // 5. Verify Balance Sheet balances (Assets 3000 == Liabilities 1200 + Equity/NetProfit 1800)
      final bs = await reportsEngine.getBalanceSheet('comp_test', 'fy_test');
      expect(bs['total_assets'], 3000.0);
      expect(bs['total_liabilities'], 1200.0);
      expect(bs['net_profit'], 1800.0);
      expect(bs['total_liabilities_and_equity'], 3000.0);
      expect(bs['difference'], 0.0); // Assets - LiabilitiesAndEquity == 0
    });
  });
}
