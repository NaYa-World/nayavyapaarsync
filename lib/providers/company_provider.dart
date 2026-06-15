import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/company.dart';
import '../data/models/financial_year.dart';
import '../data/repositories/company_repository.dart';

// ─── Repository Provider ────────────────────────────────────────────────────

final companyRepositoryProvider = Provider<CompanyRepository>((ref) {
  return CompanyRepository();
});

// ─── Companies List ─────────────────────────────────────────────────────────

class CompanyNotifier extends StateNotifier<AsyncValue<List<Company>>> {
  final CompanyRepository _repo;

  CompanyNotifier(this._repo, Ref _) : super(const AsyncValue.loading()) {
    loadCompanies();
  }

  Future<void> loadCompanies() async {
    try {
      state = const AsyncValue.loading();
      final companies = await _repo.getCompanies();
      state = AsyncValue.data(companies);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveCompany(Company company) async {
    await _repo.saveCompany(company, 'local');
    await loadCompanies();
  }

  Future<void> deleteCompany(String id) async {
    await _repo.deleteCompany(id, 'local');
    await loadCompanies();
  }
}

final companyProvider =
    StateNotifierProvider<CompanyNotifier, AsyncValue<List<Company>>>((ref) {
  final repo = ref.watch(companyRepositoryProvider);
  return CompanyNotifier(repo, ref);
});

// ─── Financial Years ─────────────────────────────────────────────────────────

class FinancialYearNotifier
    extends StateNotifier<AsyncValue<List<FinancialYear>>> {
  final CompanyRepository _repo;
  String? _companyId;

  FinancialYearNotifier(this._repo)
      : super(const AsyncValue.data([]));

  Future<void> loadForCompany(String companyId) async {
    _companyId = companyId;
    try {
      state = const AsyncValue.loading();
      final fys = await _repo.getFinancialYears(companyId);
      state = AsyncValue.data(fys);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveFinancialYear(FinancialYear fy) async {
    await _repo.saveFinancialYear(fy, 'local');
    if (_companyId != null) await loadForCompany(_companyId!);
  }

  Future<void> lockFY(String fyId, String userId) async {
    await _repo.lockFinancialYear(fyId, userId, 'local');
    if (_companyId != null) await loadForCompany(_companyId!);
  }

  Future<void> unlockFY(String fyId) async {
    await _repo.unlockFinancialYear(fyId, 'local');
    if (_companyId != null) await loadForCompany(_companyId!);
  }
}

final financialYearProvider = StateNotifierProvider<FinancialYearNotifier,
    AsyncValue<List<FinancialYear>>>((ref) {
  final repo = ref.watch(companyRepositoryProvider);
  return FinancialYearNotifier(repo);
});
