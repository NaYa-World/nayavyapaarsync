import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/expense.dart';
import '../data/repositories/expense_repository.dart';
import 'auth_provider.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository();
});

class ExpenseNotifier extends StateNotifier<AsyncValue<List<Expense>>> {
  final ExpenseRepository _repository;
  final Ref _ref;

  ExpenseNotifier(this._repository, this._ref) : super(const AsyncValue.loading()) {
    loadExpenses();
  }

  Future<void> loadExpenses() async {
    state = const AsyncValue.loading();
    try {
      final expenses = await _repository.getExpenses();
      state = AsyncValue.data(expenses);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> addExpense(Expense expense) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _repository.insertExpense(expense, deviceId);
    await loadExpenses();
  }

  Future<void> editExpense(Expense expense) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _repository.updateExpense(expense, deviceId);
    await loadExpenses();
  }

  Future<void> deleteExpense(String id) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _repository.deleteExpense(id, deviceId);
    await loadExpenses();
  }
}

final expenseProvider = StateNotifierProvider<ExpenseNotifier, AsyncValue<List<Expense>>>((ref) {
  final repository = ref.watch(expenseRepositoryProvider);
  return ExpenseNotifier(repository, ref);
});
