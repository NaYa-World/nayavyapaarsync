import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/settings.dart';
import '../data/repositories/settings_repository.dart';
import 'auth_provider.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

class SettingsNotifier extends StateNotifier<Settings?> {
  final SettingsRepository _repository;
  final Ref _ref;

  SettingsNotifier(this._repository, this._ref) : super(null) {
    loadSettings();
  }

  /// Loads the settings from SQLite
  Future<void> loadSettings() async {
    try {
      final settings = await _repository.getSettings();
      state = settings;
    } catch (_) {
      state = null;
    }
  }

  /// Updates settings, triggering audits and syncing
  Future<void> saveSettings(Settings settings) async {
    final deviceId = _ref.read(authProvider).deviceId;
    await _repository.saveSettings(settings, deviceId);
    state = settings;
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, Settings?>((ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  return SettingsNotifier(repository, ref);
});
