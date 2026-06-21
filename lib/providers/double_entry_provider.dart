import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/company.dart';
import '../data/models/financial_year.dart';
import '../data/models/ledger.dart';
import '../data/models/ledger_group.dart';
import '../data/models/bank_reconciliation.dart';
import '../data/repositories/ledger_repository.dart';
import '../data/repositories/brs_repository.dart';
import '../domain/services/voucher_engine.dart';
import '../domain/services/reports_engine.dart';
import 'company_provider.dart';

// ─── Pure Providers ───
final voucherEngineProvider = Provider<VoucherEngine>((ref) => VoucherEngine());
final reportsEngineProvider = Provider<ReportsEngine>((ref) => ReportsEngine());
final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) => LedgerRepository());
final brsRepositoryProvider = Provider<BrsRepository>((ref) => BrsRepository());

// ─── Active Company & FY Providers ───
final activeCompanyProvider = Provider<Company?>((ref) {
  final companiesState = ref.watch(companyProvider);
  return companiesState.maybeWhen(
    data: (list) => list.isNotEmpty ? list.first : null,
    orElse: () => null,
  );
});

final activeFinancialYearProvider = StateProvider<FinancialYear?>((ref) {
  final company = ref.watch(activeCompanyProvider);
  if (company == null) return null;
  
  // Try to find physical financial years matching this company
  final fysState = ref.watch(financialYearProvider);
  return fysState.maybeWhen(
    data: (list) {
      final matches = list.where((fy) => fy.companyId == company.id).toList();
      return matches.isNotEmpty ? matches.first : null;
    },
    orElse: () => null,
  );
});

// ─── Ledgers & Groups Providers ───
final ledgerGroupsProvider = FutureProvider<List<LedgerGroup>>((ref) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  return repo.getLedgerGroups();
});

class LedgersNotifier extends StateNotifier<AsyncValue<List<Ledger>>> {
  final LedgerRepository _repo;
  final Ref _ref;

  LedgersNotifier(this._repo, this._ref) : super(const AsyncValue.loading()) {
    loadLedgers();
  }

  Future<void> loadLedgers() async {
    final company = _ref.read(activeCompanyProvider);
    if (company == null) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final ledgers = await _repo.getLedgers(companyId: company.id, activeOnly: false);
      state = AsyncValue.data(ledgers);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createLedger(Ledger ledger) async {
    await _repo.createLedger(ledger);
    await loadLedgers();
  }

  Future<void> createLedgerGroup(LedgerGroup group) async {
    await _repo.createLedgerGroup(group);
    _ref.invalidate(ledgerGroupsProvider);
  }
}

final ledgersProvider = StateNotifierProvider<LedgersNotifier, AsyncValue<List<Ledger>>>((ref) {
  final repo = ref.watch(ledgerRepositoryProvider);
  return LedgersNotifier(repo, ref);
});

// ─── BRS Provider ───
class BrsNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final ReportsEngine _reportsEngine;
  final BrsRepository _brsRepo;
  final String _bankLedgerId;

  BrsNotifier(this._reportsEngine, this._brsRepo, this._bankLedgerId) : super(const AsyncValue.loading()) {
    loadBRS();
  }

  Future<void> loadBRS() async {
    state = const AsyncValue.loading();
    try {
      final data = await _reportsEngine.getBRS(_bankLedgerId);
      state = AsyncValue.data(data);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> clearInstrument(String instrumentId, DateTime clearedDate) async {
    await _brsRepo.updateInstrumentStatus(instrumentId, 'CLEARED', clearedDate);
    await loadBRS();
  }

  Future<void> saveReconciliation(BankReconciliation reconciliation) async {
    await _brsRepo.insertBankReconciliation(reconciliation);
    await loadBRS();
  }
}

final brsProvider = StateNotifierProvider.family<BrsNotifier, AsyncValue<Map<String, dynamic>>, String>((ref, bankLedgerId) {
  final engine = ref.watch(reportsEngineProvider);
  final repo = ref.watch(brsRepositoryProvider);
  return BrsNotifier(engine, repo, bankLedgerId);
});

// ─── Financial Reports Providers ───
final trialBalanceProvider = FutureProvider<List<LedgerBalance>>((ref) async {
  final engine = ref.watch(reportsEngineProvider);
  final company = ref.watch(activeCompanyProvider);
  final fy = ref.watch(activeFinancialYearProvider);
  if (company == null || fy == null) return [];
  return engine.getTrialBalance(company.id, fy.id);
});

final profitLossProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final engine = ref.watch(reportsEngineProvider);
  final company = ref.watch(activeCompanyProvider);
  final fy = ref.watch(activeFinancialYearProvider);
  if (company == null || fy == null) return {};
  return engine.getProfitLoss(company.id, fy.id);
});

final balanceSheetProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final engine = ref.watch(reportsEngineProvider);
  final company = ref.watch(activeCompanyProvider);
  final fy = ref.watch(activeFinancialYearProvider);
  if (company == null || fy == null) return {};
  return engine.getBalanceSheet(company.id, fy.id);
});
