import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:godown_management/data/database/db_helper.dart';
import 'package:godown_management/data/models/ledger_group.dart';
import 'package:godown_management/data/models/ledger.dart';
import 'package:godown_management/data/models/voucher.dart';
import 'package:godown_management/data/models/voucher_line.dart';
import 'package:godown_management/data/models/stock_movement.dart';
import 'package:godown_management/data/models/app_user.dart';
import 'package:godown_management/data/repositories/ledger_repository.dart';
import 'package:godown_management/services/voucher_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('VoucherService Unit Tests', () {
    late DbHelper dbHelper;
    late LedgerRepository ledgerRepo;
    late VoucherService voucherService;
    late AppUser testUser;

    setUp(() async {
      dbHelper = DbHelper();
      ledgerRepo = LedgerRepository();
      voucherService = VoucherService();

      testUser = AppUser(
        id: 'usr_test',
        name: 'Karthik',
        pinHash: 'hash',
        role: 'ADMIN',
        companyId: 'comp_test',
        createdAt: DateTime.now(),
      );

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

      // Pre-seed basic ledger groups and ledgers
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_assets', name: 'Current Assets', nature: 'ASSETS'));
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_cash', name: 'Cash-in-hand', parentId: 'grp_assets', nature: 'ASSETS'));
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_income', name: 'Sales Accounts', nature: 'INCOME'));
      await ledgerRepo.createLedgerGroup(LedgerGroup(id: 'grp_expenses', name: 'Purchase Accounts', nature: 'EXPENSES'));

      await ledgerRepo.createLedger(Ledger(id: 'led_cash', name: 'Cash Account', groupId: 'grp_cash', balanceType: 'DR', companyId: 'comp_test', createdAt: DateTime.now()));
      await ledgerRepo.createLedger(Ledger(id: 'led_sales', name: 'Product Sales', groupId: 'grp_income', balanceType: 'CR', companyId: 'comp_test', createdAt: DateTime.now()));
      
      // Pre-seed mock item and godown for stock movements
      await db.insert('godowns', {
        'id': 'godown_default',
        'name': 'Main Godown',
        'company_id': 'comp_test',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('items', {
        'id': 'item_1',
        'name': 'Wheat Seeds',
        'category': 'SEED',
        'hsn_code': '12099190',
        'gst_rate': 5.0,
        'primary_unit': 'BAG',
        'low_stock_threshold': 10.0,
        'created_at': DateTime.now().toIso8601String(),
        'is_deleted': 0,
      });
    });

    tearDown(() async {
      await dbHelper.close();
    });

    test('postVoucher creates balanced double-entry voucher successfully', () async {
      final draft = VoucherDraft(
        id: 'vch_test_1',
        voucherNo: 'VCH-001',
        type: 'SALE',
        date: DateTime(2026, 6, 15),
        narration: 'Test balanced sale',
        companyId: 'comp_test',
        fyId: 'fy_test',
        lines: [
          VoucherLineDraft(ledgerId: 'led_cash', drAmount: 1000.0, crAmount: 0.0),
          VoucherLineDraft(ledgerId: 'led_sales', drAmount: 0.0, crAmount: 1000.0),
        ],
        inventoryMovements: [
          StockMovementDraft(stockItemId: 'item_1', godownId: 'godown_default', qty: 10.0, rate: 100.0, movementType: 'OUT'),
        ],
      );

      final posted = await voucherService.postVoucher(draft, testUser);
      expect(posted.id, 'vch_test_1');
      expect(posted.isCancelled, false);
      expect(posted.isDeleted, false);

      final db = await dbHelper.database;

      // Verify voucher in DB
      final vRows = await db.query('vouchers', where: 'id = ?', whereArgs: ['vch_test_1']);
      expect(vRows.length, 1);
      expect(vRows.first['is_cancelled'], 0);

      // Verify voucher lines in DB
      final vlRows = await db.query('voucher_lines', where: 'voucher_id = ?', whereArgs: ['vch_test_1']);
      expect(vlRows.length, 2);

      // Verify stock movements in DB
      final smRows = await db.query('stock_movements', where: 'ref_voucher_id = ?', whereArgs: ['vch_test_1']);
      expect(smRows.length, 1);
      expect(smRows.first['qty'], 10.0);

      // Verify sync queue and audit logs
      final syncRows = await db.query('sync_queue', where: 'record_id = ?', whereArgs: ['vch_test_1']);
      expect(syncRows.length, 1);
      expect(syncRows.first['operation'], 'CREATE');

      final auditRows = await db.query('audit_logs', where: 'record_id = ?', whereArgs: ['vch_test_1']);
      expect(auditRows.length, 1);
      expect(auditRows.first['action'], 'CREATE');
    });

    test('postVoucher throws exception when entries are unbalanced', () async {
      final draft = VoucherDraft(
        id: 'vch_test_unbalanced',
        voucherNo: 'VCH-002',
        type: 'SALE',
        date: DateTime(2026, 6, 15),
        companyId: 'comp_test',
        fyId: 'fy_test',
        lines: [
          VoucherLineDraft(ledgerId: 'led_cash', drAmount: 1000.0, crAmount: 0.0),
          VoucherLineDraft(ledgerId: 'led_sales', drAmount: 0.0, crAmount: 950.0), // unbalanced by 50
        ],
      );

      expect(
        () => voucherService.postVoucher(draft, testUser),
        throwsA(isA<Exception>()),
      );
    });

    test('cancelVoucher reverses posting and deletes stock movements without deleting parent', () async {
      final draft = VoucherDraft(
        id: 'vch_test_cancel',
        voucherNo: 'VCH-003',
        type: 'SALE',
        date: DateTime(2026, 6, 15),
        companyId: 'comp_test',
        fyId: 'fy_test',
        lines: [
          VoucherLineDraft(ledgerId: 'led_cash', drAmount: 1000.0, crAmount: 0.0),
          VoucherLineDraft(ledgerId: 'led_sales', drAmount: 0.0, crAmount: 1000.0),
        ],
        inventoryMovements: [
          StockMovementDraft(stockItemId: 'item_1', godownId: 'godown_default', qty: 5.0, rate: 200.0, movementType: 'OUT'),
        ],
      );

      await voucherService.postVoucher(draft, testUser);

      // Perform cancellation
      await voucherService.cancelVoucher('vch_test_cancel', testUser);

      final db = await dbHelper.database;

      // Verify voucher isCancelled = 1
      final vRows = await db.query('vouchers', where: 'id = ?', whereArgs: ['vch_test_cancel']);
      expect(vRows.first['is_cancelled'], 1);
      expect(vRows.first['is_deleted'], 0);

      // Verify stock movements are deleted
      final smRows = await db.query('stock_movements', where: 'ref_voucher_id = ?', whereArgs: ['vch_test_cancel']);
      expect(smRows.isEmpty, true);

      // Verify sync queue and audit log contains EDIT/cancellation logs
      final syncRows = await db.query('sync_queue', where: "record_id = ? AND operation = 'EDIT'", whereArgs: ['vch_test_cancel']);
      expect(syncRows.length, 1);

      final auditRows = await db.query('audit_logs', where: "record_id = ? AND action = 'EDIT'", whereArgs: ['vch_test_cancel']);
      expect(auditRows.length, 1);
    });

    test('deleteVoucher soft deletes the voucher and removes stock movements', () async {
      final draft = VoucherDraft(
        id: 'vch_test_delete',
        voucherNo: 'VCH-004',
        type: 'SALE',
        date: DateTime(2026, 6, 15),
        companyId: 'comp_test',
        fyId: 'fy_test',
        lines: [
          VoucherLineDraft(ledgerId: 'led_cash', drAmount: 1000.0, crAmount: 0.0),
          VoucherLineDraft(ledgerId: 'led_sales', drAmount: 0.0, crAmount: 1000.0),
        ],
        inventoryMovements: [
          StockMovementDraft(stockItemId: 'item_1', godownId: 'godown_default', qty: 5.0, rate: 200.0, movementType: 'OUT'),
        ],
      );

      await voucherService.postVoucher(draft, testUser);

      // Perform deletion
      await voucherService.deleteVoucher('vch_test_delete', testUser);

      final db = await dbHelper.database;

      // Verify voucher is_deleted = 1
      final vRows = await db.query('vouchers', where: 'id = ?', whereArgs: ['vch_test_delete']);
      expect(vRows.first['is_deleted'], 1);

      // Verify stock movements are deleted
      final smRows = await db.query('stock_movements', where: 'ref_voucher_id = ?', whereArgs: ['vch_test_delete']);
      expect(smRows.isEmpty, true);

      // Verify sync queue and audit logs
      final syncRows = await db.query('sync_queue', where: "record_id = ? AND operation = 'DELETE'", whereArgs: ['vch_test_delete']);
      expect(syncRows.length, 1);
    });

    test('alterVoucher cancels old voucher and posts new modified draft', () async {
      final draft = VoucherDraft(
        id: 'vch_old',
        voucherNo: 'VCH-005',
        type: 'SALE',
        date: DateTime(2026, 6, 15),
        companyId: 'comp_test',
        fyId: 'fy_test',
        lines: [
          VoucherLineDraft(ledgerId: 'led_cash', drAmount: 1000.0, crAmount: 0.0),
          VoucherLineDraft(ledgerId: 'led_sales', drAmount: 0.0, crAmount: 1000.0),
        ],
        inventoryMovements: [
          StockMovementDraft(stockItemId: 'item_1', godownId: 'godown_default', qty: 5.0, rate: 200.0, movementType: 'OUT'),
        ],
      );

      await voucherService.postVoucher(draft, testUser);

      final modifiedDraft = VoucherDraft(
        id: 'vch_new',
        voucherNo: 'VCH-005-REV',
        type: 'SALE',
        date: DateTime(2026, 6, 15),
        companyId: 'comp_test',
        fyId: 'fy_test',
        lines: [
          VoucherLineDraft(ledgerId: 'led_cash', drAmount: 1200.0, crAmount: 0.0),
          VoucherLineDraft(ledgerId: 'led_sales', drAmount: 0.0, crAmount: 1200.0),
        ],
        inventoryMovements: [
          StockMovementDraft(stockItemId: 'item_1', godownId: 'godown_default', qty: 6.0, rate: 200.0, movementType: 'OUT'),
        ],
      );

      final altered = await voucherService.alterVoucher('vch_old', modifiedDraft, testUser);
      expect(altered.id, 'vch_new');

      final db = await dbHelper.database;

      // Verify old voucher is cancelled
      final oldVRows = await db.query('vouchers', where: 'id = ?', whereArgs: ['vch_old']);
      expect(oldVRows.first['is_cancelled'], 1);

      // Verify old stock movements are deleted
      final oldSmRows = await db.query('stock_movements', where: 'ref_voucher_id = ?', whereArgs: ['vch_old']);
      expect(oldSmRows.isEmpty, true);

      // Verify new voucher is active and modified
      final newVRows = await db.query('vouchers', where: 'id = ?', whereArgs: ['vch_new']);
      expect(newVRows.first['is_cancelled'], 0);
      expect(newVRows.first['is_deleted'], 0);

      final newVlRows = await db.query('voucher_lines', where: 'voucher_id = ?', whereArgs: ['vch_new']);
      expect(newVlRows.first['dr_amount'] == 1200.0 || newVlRows.last['dr_amount'] == 1200.0, true);

      final newSmRows = await db.query('stock_movements', where: 'ref_voucher_id = ?', whereArgs: ['vch_new']);
      expect(newSmRows.length, 1);
      expect(newSmRows.first['qty'], 6.0);
    });
  });
}
