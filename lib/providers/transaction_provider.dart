import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/payment.dart';
import '../data/models/purchase.dart';
import '../data/models/sale.dart';
import '../data/repositories/payment_repository.dart';
import '../data/repositories/purchase_repository.dart';
import '../data/repositories/sale_repository.dart';
import '../services/sync_queue_service.dart';
import 'auth_provider.dart';
import 'backup_provider.dart';
import 'item_provider.dart';
import 'party_provider.dart';
import 'double_entry_provider.dart';

class TransactionState {
  final List<Purchase> purchases;
  final List<Sale> sales;
  final List<Payment> payments;
  final bool isLoading;

  TransactionState({
    this.purchases = const [],
    this.sales = const [],
    this.payments = const [],
    this.isLoading = false,
  });

  TransactionState copyWith({
    List<Purchase>? purchases,
    List<Sale>? sales,
    List<Payment>? payments,
    bool? isLoading,
  }) {
    return TransactionState(
      purchases: purchases ?? this.purchases,
      sales: sales ?? this.sales,
      payments: payments ?? this.payments,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) => PurchaseRepository());
final saleRepositoryProvider = Provider<SaleRepository>((ref) => SaleRepository());
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) => PaymentRepository());

class TransactionNotifier extends StateNotifier<TransactionState> {
  final PurchaseRepository _purchaseRepo;
  final SaleRepository _saleRepo;
  final PaymentRepository _paymentRepo;
  final Ref _ref;

  TransactionNotifier(this._purchaseRepo, this._saleRepo, this._paymentRepo, this._ref)
      : super(TransactionState()) {
    loadAllTransactions();
  }

  /// Loads all purchases, sales, and payments from repositories
  Future<void> loadAllTransactions() async {
    state = state.copyWith(isLoading: true);
    try {
      final company = _ref.read(activeCompanyProvider);
      final companyId = company?.id ?? 'company_default';

      final purchases = await _purchaseRepo.getPurchases(companyId: companyId);
      final sales = await _saleRepo.getSales(companyId: companyId);
      final payments = await _paymentRepo.getPayments(companyId: companyId);

      state = TransactionState(
        purchases: purchases,
        sales: sales,
        payments: payments,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Triggers background database sync to GDrive (non-blocking)
  void _triggerBackgroundSync() {
    final deviceId = _ref.read(authProvider).deviceId;
    SyncQueueService().triggerSync(deviceId).then((hasChanged) {
      if (hasChanged) {
        loadAllTransactions();
        _refreshDependentStates();
      } else {
        _ref.read(backupProvider.notifier).checkUnsyncedStatus();
      }
    });
  }

  /// Refreshes dependent states (stock and party balances)
  void _refreshDependentStates() {
    _ref.read(itemProvider.notifier).loadItems();
    _ref.read(partyProvider.notifier).loadParties();
    _ref.read(backupProvider.notifier).checkUnsyncedStatus();
  }

  // ================= PURCHASES =================

  Future<void> addPurchase(Purchase purchase, List<PurchaseItem> items) async {
    final deviceId = _ref.read(authProvider).deviceId;
    final company = _ref.read(activeCompanyProvider);
    final companyId = company?.id ?? 'company_default';
    await _purchaseRepo.insertPurchase(purchase, items, deviceId, companyId: companyId);
    await loadAllTransactions();
    _refreshDependentStates();
    _triggerBackgroundSync();
  }

  Future<void> editPurchase(Purchase purchase, List<PurchaseItem> items) async {
    final deviceId = _ref.read(authProvider).deviceId;
    final company = _ref.read(activeCompanyProvider);
    final companyId = company?.id ?? 'company_default';
    await _purchaseRepo.updatePurchase(purchase, items, deviceId, companyId: companyId);
    await loadAllTransactions();
    _refreshDependentStates();
    _triggerBackgroundSync();
  }

  Future<void> deletePurchase(String id) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _purchaseRepo.deletePurchase(id, deviceId);
    await loadAllTransactions();
    _refreshDependentStates();
    _triggerBackgroundSync();
  }

  // ================= SALES =================

  Future<void> addSale(Sale sale, List<SaleItem> items) async {
    final deviceId = _ref.read(authProvider).deviceId;
    final company = _ref.read(activeCompanyProvider);
    final companyId = company?.id ?? 'company_default';
    await _saleRepo.insertSale(sale, items, deviceId, companyId: companyId);
    await loadAllTransactions();
    _refreshDependentStates();
    _triggerBackgroundSync();
  }

  Future<void> editSale(Sale sale, List<SaleItem> items) async {
    final deviceId = _ref.read(authProvider).deviceId;
    final company = _ref.read(activeCompanyProvider);
    final companyId = company?.id ?? 'company_default';
    await _saleRepo.updateSale(sale, items, deviceId, companyId: companyId);
    await loadAllTransactions();
    _refreshDependentStates();
    _triggerBackgroundSync();
  }

  Future<void> deleteSale(String id) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _saleRepo.deleteSale(id, deviceId);
    await loadAllTransactions();
    _refreshDependentStates();
    _triggerBackgroundSync();
  }

  // ================= PAYMENTS =================

  Future<void> addPayment(Payment payment) async {
    final deviceId = _ref.read(authProvider).deviceId;
    final company = _ref.read(activeCompanyProvider);
    final companyId = company?.id ?? 'company_default';
    await _paymentRepo.insertPayment(payment, deviceId, companyId: companyId);
    await loadAllTransactions();
    _refreshDependentStates();
    _triggerBackgroundSync();
  }

  Future<void> editPayment(Payment payment) async {
    final deviceId = _ref.read(authProvider).deviceId;
    final company = _ref.read(activeCompanyProvider);
    final companyId = company?.id ?? 'company_default';
    await _paymentRepo.updatePayment(payment, deviceId, companyId: companyId);
    await loadAllTransactions();
    _refreshDependentStates();
    _triggerBackgroundSync();
  }

  Future<void> deletePayment(String id) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _paymentRepo.deletePayment(id, deviceId);
    await loadAllTransactions();
    _refreshDependentStates();
    _triggerBackgroundSync();
  }
}

final transactionProvider = StateNotifierProvider<TransactionNotifier, TransactionState>((ref) {
  final pRepo = ref.watch(purchaseRepositoryProvider);
  final sRepo = ref.watch(saleRepositoryProvider);
  final payRepo = ref.watch(paymentRepositoryProvider);
  ref.watch(activeCompanyProvider);
  return TransactionNotifier(pRepo, sRepo, payRepo, ref);
});
