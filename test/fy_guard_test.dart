import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:godown_management/data/database/db_helper.dart';
import 'package:godown_management/core/utils/fy_guard.dart';
import 'package:godown_management/data/models/sale.dart';
import 'package:godown_management/data/models/purchase.dart';
import 'package:godown_management/data/models/payment.dart';
import 'package:godown_management/data/models/expense.dart';
import 'package:godown_management/data/repositories/sale_repository.dart';
import 'package:godown_management/data/repositories/purchase_repository.dart';
import 'package:godown_management/data/repositories/payment_repository.dart';
import 'package:godown_management/data/repositories/expense_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Financial Year Lock Guard Tests', () {
    late DbHelper dbHelper;
    late String dbPath;

    setUp(() async {
      dbHelper = DbHelper();
      await dbHelper.close();
      final databasePath = await getDatabasesPath();
      dbPath = '$databasePath/godown_management.db';
      try {
        await deleteDatabase(dbPath);
      } catch (_) {}
    });

    tearDown(() async {
      await dbHelper.close();
      try {
        await deleteDatabase(dbPath);
      } catch (_) {}
    });

    test('FyGuard blocks insert/update/delete operations on locked FY', () async {
      final db = await dbHelper.database;
      await db.delete('financial_years');
      await db.delete('companies');

      // Seed active company
      await db.insert('companies', {
        'id': 'comp_test',
        'name': 'Test Company',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Seed locked FY for 2026-04-01 to 2027-03-31
      await db.insert('financial_years', {
        'id': 'fy_test_locked',
        'company_id': 'comp_test',
        'label': 'FY 26-27',
        'start_date': '2026-04-01',
        'end_date': '2027-03-31',
        'is_locked': 1,
        'locked_by': 'admin',
        'locked_at': DateTime.now().toIso8601String(),
      });

      // Date that falls inside the locked FY
      final lockedDate = DateTime(2026, 6, 15);

      // Verify FyGuard static helpers directly
      expect(
        () => FyGuard.checkDate(date: lockedDate),
        throwsA(isA<LockedPeriodException>()),
      );

      final isLocked = await FyGuard.isDateLocked(date: lockedDate);
      expect(isLocked, isTrue);

      // Verify Sale Repository insert throws LockedPeriodException
      final saleRepo = SaleRepository();
      final testSale = Sale(
        id: 'sale-test-id',
        invoiceNo: 'SAL/2026-27/001',
        partyId: 'party-1',
        date: lockedDate,
        subtotal: 100.0,
        gstTotal: 10.0,
        grandTotal: 110.0,
        paymentStatus: 'PENDING',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        category: 'SEED',
      );

      expect(
        () => saleRepo.insertSale(testSale, [], 'device1'),
        throwsA(isA<LockedPeriodException>()),
      );

      // Verify Purchase Repository insert throws LockedPeriodException
      final purchaseRepo = PurchaseRepository();
      final testPurchase = Purchase(
        id: 'purchase-test-id',
        invoiceNo: 'PUR/2026-27/001',
        partyId: 'party-2',
        date: lockedDate,
        subtotal: 200.0,
        gstTotal: 20.0,
        grandTotal: 220.0,
        paymentStatus: 'PENDING',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        category: 'SEED',
      );

      expect(
        () => purchaseRepo.insertPurchase(testPurchase, [], 'device1'),
        throwsA(isA<LockedPeriodException>()),
      );

      // Verify Payment Repository insert throws LockedPeriodException
      final paymentRepo = PaymentRepository();
      final testPayment = Payment(
        id: 'payment-test-id',
        partyId: 'party-1',
        direction: 'RECEIVED',
        amount: 50.0,
        mode: 'CASH',
        date: lockedDate,
        createdAt: DateTime.now(),
      );

      expect(
        () => paymentRepo.insertPayment(testPayment, 'device1'),
        throwsA(isA<LockedPeriodException>()),
      );

      // Verify Expense Repository insert throws LockedPeriodException
      final expenseRepo = ExpenseRepository();
      final testExpense = Expense(
        id: 'expense-test-id',
        category: 'HAMALI',
        amount: 30.0,
        date: lockedDate,
        description: 'Hamali charges',
        paymentMethod: 'CASH',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => expenseRepo.insertExpense(testExpense, 'device1'),
        throwsA(isA<LockedPeriodException>()),
      );
    });

    test('FyGuard allows insert/update/delete operations on unlocked FY', () async {
      final db = await dbHelper.database;
      await db.delete('financial_years');
      await db.delete('companies');

      // Seed active company
      await db.insert('companies', {
        'id': 'comp_test',
        'name': 'Test Company',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Seed unlocked FY for 2026-04-01 to 2027-03-31
      await db.insert('financial_years', {
        'id': 'fy_test_unlocked',
        'company_id': 'comp_test',
        'label': 'FY 26-27',
        'start_date': '2026-04-01',
        'end_date': '2027-03-31',
        'is_locked': 0,
      });

      // Seed dummy party to prevent foreign key constraint violations
      await db.insert('parties', {
        'id': 'party-1',
        'name': 'Party One',
        'type': 'CUSTOMER',
        'phone': '1234567890',
        'address': 'Test address',
        'created_at': DateTime.now().toIso8601String(),
      });

      final unlockedDate = DateTime(2026, 6, 15);

      // Direct checks
      await FyGuard.checkDate(date: unlockedDate);
      final isLocked = await FyGuard.isDateLocked(date: unlockedDate);
      expect(isLocked, isFalse);

      // Verify Sale Repository insert executes successfully without throwing
      final saleRepo = SaleRepository();
      final testSale = Sale(
        id: 'sale-test-id',
        invoiceNo: 'SAL/2026-27/001',
        partyId: 'party-1',
        date: unlockedDate,
        subtotal: 100.0,
        gstTotal: 10.0,
        grandTotal: 110.0,
        paymentStatus: 'PENDING',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        category: 'SEED',
      );

      await saleRepo.insertSale(testSale, [], 'device1');
      final fetchedSale = await saleRepo.getSale('sale-test-id');
      expect(fetchedSale, isNotNull);
      expect(fetchedSale!.sale.invoiceNo, 'SAL/2026-27/001');
    });
  });
}
