import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/party.dart';
import '../data/repositories/party_repository.dart';
import 'auth_provider.dart';

class PartyWithBalance {
  final Party party;
  final double outstandingBalance;
  final String balanceType; // 'DR' or 'CR'

  PartyWithBalance({
    required this.party,
    required this.outstandingBalance,
    required this.balanceType,
  });
}

final partyRepositoryProvider = Provider<PartyRepository>((ref) {
  return PartyRepository();
});

class PartyNotifier extends StateNotifier<AsyncValue<List<PartyWithBalance>>> {
  final PartyRepository _repository;
  final Ref _ref;

  PartyNotifier(this._repository, this._ref) : super(const AsyncValue.loading()) {
    loadParties();
  }

  /// Loads all parties and calculates their outstanding balances dynamically
  Future<void> loadParties() async {
    state = const AsyncValue.loading();
    try {
      final parties = await _repository.getParties();
      final List<PartyWithBalance> partiesWithBalance = [];

      for (final party in parties) {
        final balanceInfo = await _repository.getOutstandingBalance(party.id);
        partiesWithBalance.add(PartyWithBalance(
          party: party,
          outstandingBalance: balanceInfo['balance'] as double,
          balanceType: balanceInfo['type'] as String,
        ));
      }

      state = AsyncValue.data(partiesWithBalance);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Adds a new party and refreshes the list
  Future<void> addParty(Party party) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _repository.insertParty(party, deviceId);
    await loadParties();
  }

  /// Edits an existing party and refreshes the list
  Future<void> editParty(Party party) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _repository.updateParty(party, deviceId);
    await loadParties();
  }

  /// Soft-deletes a party and refreshes the list
  Future<void> deleteParty(String id) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _repository.deleteParty(id, deviceId);
    await loadParties();
  }
}

final partyProvider = StateNotifierProvider<PartyNotifier, AsyncValue<List<PartyWithBalance>>>((ref) {
  final repository = ref.watch(partyRepositoryProvider);
  return PartyNotifier(repository, ref);
});

/// Exposes all supplier accounts
final supplierProvider = Provider<List<PartyWithBalance>>((ref) {
  final partiesState = ref.watch(partyProvider);
  return partiesState.maybeWhen(
    data: (list) => list.where((p) => p.party.type == 'SUPPLIER').toList(),
    orElse: () => [],
  );
});

/// Exposes all customer accounts
final customerProvider = Provider<List<PartyWithBalance>>((ref) {
  final partiesState = ref.watch(partyProvider);
  return partiesState.maybeWhen(
    data: (list) => list.where((p) => p.party.type == 'CUSTOMER').toList(),
    orElse: () => [],
  );
});
