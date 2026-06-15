import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:godown_management/data/database/db_helper.dart';
import 'package:godown_management/data/models/company.dart';
import 'package:godown_management/data/models/financial_year.dart';
import 'package:godown_management/data/models/app_user.dart';
import 'package:godown_management/data/models/payment.dart';
import 'package:godown_management/data/repositories/company_repository.dart';
import 'package:godown_management/data/repositories/user_repository.dart';
import 'package:godown_management/data/repositories/payment_repository.dart';
import 'package:godown_management/core/utils/fy_guard.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('TallyDroid Phase 2 E2E Workflow Tests', () {
    late DbHelper dbHelper;
    late CompanyRepository companyRepo;
    late UserRepository userRepo;
    late PaymentRepository paymentRepo;

    setUp(() async {
      dbHelper = DbHelper();
      companyRepo = CompanyRepository();
      userRepo = UserRepository();
      paymentRepo = PaymentRepository();

      await dbHelper.close();
      final databasePath = await getDatabasesPath();
      final path = '$databasePath/godown_management.db';
      try {
        await deleteDatabase(path);
      } catch (_) {}
    });

    tearDown(() async {
      await dbHelper.close();
    });

    test('E2E Lifecycle: Multi-Company, User Roles with PIN, Lock Guard, and Cheque Payments', () async {
      final db = await dbHelper.database;

      // 0. Reset auto-seeded data for absolute control
      await db.delete('financial_years');
      await db.delete('companies');
      await db.delete('app_users');

      // ─── 1. Company Setup ───
      final compA = Company(
        id: 'company-a',
        name: 'Vedic Agro Seeds',
        gstin: '36ABCDE1234F1Z5',
        address: 'Warangal Highway, TS',
        phone: '9988776655',
        state: 'Telangana',
        stateCode: '36',
        isActive: true,
        createdAt: DateTime.now(),
      );

      final compB = Company(
        id: 'company-b',
        name: 'Delta Fertilizers',
        gstin: '36XYZAB5678C1Z9',
        address: 'Nalgonda Bypass, TS',
        phone: '9900881122',
        state: 'Telangana',
        stateCode: '36',
        isActive: false, // Inactive company
        createdAt: DateTime.now(),
      );

      await companyRepo.saveCompany(compA, 'device-1');
      await companyRepo.saveCompany(compB, 'device-1');

      final activeCompanies = await companyRepo.getCompanies();
      expect(activeCompanies.length, 1);
      expect(activeCompanies.first.id, 'company-a');
      expect(activeCompanies.first.name, 'Vedic Agro Seeds');

      // ─── 2. Financial Year Setup ───
      final fy26 = FinancialYear(
        id: 'fy-2026',
        companyId: 'company-a',
        label: 'FY 26-27',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2027, 3, 31),
        isLocked: false,
      );

      await companyRepo.saveFinancialYear(fy26, 'device-1');

      final fys = await companyRepo.getFinancialYears('company-a');
      expect(fys.length, 1);
      expect(fys.first.label, 'FY 26-27');

      // ─── 3. User & PIN Auth Setup ───
      final userCA = AppUser(
        id: 'user-ca-1',
        name: 'CA Srinivasan',
        pinHash: '1234', // Raw PIN (will be hashed by repository/notifier)
        role: 'CA',
        companyId: 'company-a',
        isActive: true,
        createdAt: DateTime.now(),
      );

      // Create user and hash PIN
      await userRepo.createUser(
        name: userCA.name,
        plainPin: '1234',
        role: userCA.role,
        companyId: userCA.companyId,
        deviceId: 'device-1',
      );

      final users = await userRepo.getUsers();
      expect(users.length, 1);
      expect(users.first.name, 'CA Srinivasan');
      expect(users.first.role, 'CA');

      // Verify PIN Auth works successfully
      final authSuccess = userRepo.validatePin('1234', users.first.pinHash);
      expect(authSuccess, isTrue);

      final authFail = userRepo.validatePin('9999', users.first.pinHash);
      expect(authFail, isFalse);

      // ─── 4. FY Lock Guard Verification ───
      final targetDate = DateTime(2026, 6, 15);

      // Verify no locks yet, transaction checks pass
      await FyGuard.checkDate(date: targetDate, companyId: 'company-a');

      // Lock the Financial Year
      await companyRepo.lockFinancialYear('fy-2026', users.first.id, 'device-1');

      final lockedFys = await companyRepo.getFinancialYears('company-a');
      expect(lockedFys.first.isLocked, isTrue);
      expect(lockedFys.first.lockedBy, users.first.id);

      // Verify that FyGuard now blocks transactions
      expect(
        () => FyGuard.checkDate(date: targetDate, companyId: 'company-a'),
        throwsA(isA<LockedPeriodException>()),
      );

      // Unlock the Financial Year
      await companyRepo.unlockFinancialYear('fy-2026', 'device-1');

      final unlockedFys = await companyRepo.getFinancialYears('company-a');
      expect(unlockedFys.first.isLocked, isFalse);

      // Verify operations can pass again
      await FyGuard.checkDate(date: targetDate, companyId: 'company-a');

      // ─── 5. Cheque Payment Verification ───
      // Add a dummy party for payments foreign key
      await db.insert('parties', {
        'id': 'party-x',
        'name': 'Farmer Raju',
        'type': 'CUSTOMER',
        'phone': '9900000000',
        'address': 'Khammam',
        'created_at': DateTime.now().toIso8601String(),
      });

      final paymentDate = DateTime(2026, 6, 10);
      final chequePayment = Payment(
        id: 'pay-cheque-1',
        partyId: 'party-x',
        direction: 'RECEIVED',
        amount: 45000.0,
        mode: 'CHEQUE',
        date: paymentDate,
        createdAt: DateTime.now(),
        chequeNo: 'CHQ-778899',
        chequeBank: 'HDFC Bank',
        chequeDate: DateTime(2026, 6, 12),
        chequeStatus: 'ISSUED',
      );

      await paymentRepo.insertPayment(chequePayment, 'device-1');

      final dbPayment = await paymentRepo.getPayment('pay-cheque-1');
      expect(dbPayment, isNotNull);
      expect(dbPayment!.mode, 'CHEQUE');
      expect(dbPayment.chequeNo, 'CHQ-778899');
      expect(dbPayment.chequeBank, 'HDFC Bank');
      expect(dbPayment.chequeStatus, 'ISSUED');
      expect(dbPayment.isCheque, isTrue);
    });
  });
}
