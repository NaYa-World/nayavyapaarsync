import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/item.dart';
import '../data/repositories/item_repository.dart';
import 'auth_provider.dart';
import 'double_entry_provider.dart';

class ItemWithStock {
  final Item item;
  final double currentStock;

  ItemWithStock({required this.item, required this.currentStock});

  double? get totalWeightKg {
    if (item.primaryUnit == 'BAG' && item.bagWeightKg != null) {
      return currentStock * item.bagWeightKg!;
    } else if (item.primaryUnit == 'BOX' && item.boxWeightKg != null) {
      return currentStock * item.boxWeightKg!;
    }
    return null;
  }
}

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  return ItemRepository();
});

class ItemNotifier extends StateNotifier<AsyncValue<List<ItemWithStock>>> {
  final ItemRepository _repository;
  final Ref _ref;

  ItemNotifier(this._repository, this._ref) : super(const AsyncValue.loading()) {
    loadItems();
  }

  /// Loads all items and calculates their current stock on-the-fly
  Future<void> loadItems() async {
    state = const AsyncValue.loading();
    try {
      final company = _ref.read(activeCompanyProvider);
      final companyId = company?.id ?? 'company_default';

      final items = await _repository.getItems(companyId: companyId);
      final List<ItemWithStock> itemsWithStock = [];
      
      for (final item in items) {
        final stock = await _repository.getItemStock(item.id);
        itemsWithStock.add(ItemWithStock(item: item, currentStock: stock));
      }

      state = AsyncValue.data(itemsWithStock);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Adds a new item and refreshes the list
  Future<void> addItem(Item item) async {
    final deviceId = _ref.read(authProvider).deviceId;
    final company = _ref.read(activeCompanyProvider);
    final companyId = company?.id ?? 'company_default';
    await _repository.insertItem(item, deviceId, companyId: companyId);
    await loadItems();
  }

  /// Edits an existing item and refreshes the list
  Future<void> editItem(Item item) async {
    final deviceId = _ref.read(authProvider).deviceId;
    final company = _ref.read(activeCompanyProvider);
    final companyId = company?.id ?? 'company_default';
    await _repository.updateItem(item, deviceId, companyId: companyId);
    await loadItems();
  }

  /// Soft-deletes an item and refreshes the list
  Future<void> deleteItem(String id) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _repository.deleteItem(id, deviceId);
    await loadItems();
  }
}

final itemProvider = StateNotifierProvider<ItemNotifier, AsyncValue<List<ItemWithStock>>>((ref) {
  final repository = ref.watch(itemRepositoryProvider);
  ref.watch(activeCompanyProvider);
  return ItemNotifier(repository, ref);
});

/// Exposes only items that are below or equal to their low stock threshold
final lowStockItemsProvider = Provider<List<ItemWithStock>>((ref) {
  final itemsState = ref.watch(itemProvider);
  return itemsState.maybeWhen(
    data: (items) => items.where((i) => i.currentStock <= i.item.lowStockThreshold).toList(),
    orElse: () => [],
  );
});
