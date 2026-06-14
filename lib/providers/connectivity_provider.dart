import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NetworkStatus { online, offline }

class ConnectivityNotifier extends StateNotifier<NetworkStatus> {
  late StreamSubscription<List<ConnectivityResult>> _subscription;

  ConnectivityNotifier() : super(NetworkStatus.offline) {
    _initConnectivity();
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      _updateStatus(results);
    });
  }

  Future<void> _initConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      await _updateStatus(results);
    } catch (_) {
      state = NetworkStatus.offline;
    }
  }

  Future<void> _updateStatus(List<ConnectivityResult> results) async {
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      state = NetworkStatus.offline;
    } else {
      state = NetworkStatus.online;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final connectivityProvider = StateNotifierProvider<ConnectivityNotifier, NetworkStatus>((ref) {
  return ConnectivityNotifier();
});

final isOnlineProvider = Provider<bool>((ref) {
  final status = ref.watch(connectivityProvider);
  return status == NetworkStatus.online;
});
