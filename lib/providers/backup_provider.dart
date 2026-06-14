import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/backup_meta.dart';
import '../data/repositories/backup_repository.dart';
import '../services/gdrive_service.dart';
import '../services/sync_queue_service.dart';
import 'auth_provider.dart';
import 'transaction_provider.dart';
import 'item_provider.dart';
import 'party_provider.dart';

class BackupState {
  final List<GDriveFileMeta> backups;
  final bool isLoading;
  final bool hasUnsyncedChanges;
  final BackupMeta? lastBackup;

  BackupState({
    this.backups = const [],
    this.isLoading = false,
    this.hasUnsyncedChanges = false,
    this.lastBackup,
  });

  BackupState copyWith({
    List<GDriveFileMeta>? backups,
    bool? isLoading,
    bool? hasUnsyncedChanges,
    BackupMeta? lastBackup,
  }) {
    return BackupState(
      backups: backups ?? this.backups,
      isLoading: isLoading ?? this.isLoading,
      hasUnsyncedChanges: hasUnsyncedChanges ?? this.hasUnsyncedChanges,
      lastBackup: lastBackup ?? this.lastBackup,
    );
  }
}

final backupRepositoryProvider = Provider<BackupRepository>((ref) => BackupRepository());

class BackupNotifier extends StateNotifier<BackupState> {
  final BackupRepository _repository;
  final GDriveService _gdriveService = GDriveService();
  final Ref _ref;

  BackupNotifier(this._repository, this._ref) : super(BackupState()) {
    initBackupState();
  }

  Future<void> initBackupState() async {
    await checkUnsyncedStatus();
    await loadLocalBackupMeta();
    await refreshRemoteBackups();
  }

  /// Checks if there are pending unsynced changes in the SQLite queue
  Future<void> checkUnsyncedStatus() async {
    final hasChanges = await _repository.hasUnsyncedChanges();
    state = state.copyWith(hasUnsyncedChanges: hasChanges);
  }

  /// Loads the latest backup metadata from the local database
  Future<void> loadLocalBackupMeta() async {
    final list = await _repository.getBackupMetas();
    if (list.isNotEmpty) {
      // Find the latest successful backup, or just the absolute latest
      final successfulBackups = list.where((b) => b.status == 'SUCCESS').toList();
      state = state.copyWith(
        lastBackup: successfulBackups.isNotEmpty ? successfulBackups.first : list.first,
      );
    }
  }

  /// Fetches the file backup list from Google Drive (if online)
  Future<void> refreshRemoteBackups() async {
    final isOnline = await SyncQueueService().isOnline();
    if (!isOnline) return;

    state = state.copyWith(isLoading: true);
    try {
      final list = await _gdriveService.listSnapshots();
      state = state.copyWith(backups: list, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Triggers a manual full backup upload to Google Drive
  Future<bool> runManualBackup() async {
    state = state.copyWith(isLoading: true);
    final deviceId = _ref.read(authProvider).deviceId;

    try {
      final hasChanged = await SyncQueueService().triggerSync(deviceId);
      
      // Reload states
      await loadLocalBackupMeta();
      await refreshRemoteBackups();
      await checkUnsyncedStatus();
      
      if (hasChanged) {
        // Reload transactions if remote changes were applied
        await _ref.read(transactionProvider.notifier).loadAllTransactions();
        _ref.read(itemProvider.notifier).loadItems();
        _ref.read(partyProvider.notifier).loadParties();
      }

      state = state.copyWith(isLoading: false);
      return true;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }
}

final backupProvider = StateNotifierProvider<BackupNotifier, BackupState>((ref) {
  final repo = ref.watch(backupRepositoryProvider);
  return BackupNotifier(repo, ref);
});
