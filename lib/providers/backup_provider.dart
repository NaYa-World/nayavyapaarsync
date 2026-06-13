import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/backup_meta.dart';
import '../data/repositories/backup_repository.dart';
import '../services/backup_service.dart';
import '../services/gdrive_service.dart';
import '../services/sync_queue_service.dart';
import 'auth_provider.dart';

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
  final BackupService _backupService = BackupService();
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
      final list = await _gdriveService.listBackups();
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
      final meta = await _backupService.performBackup(deviceId);
      await loadLocalBackupMeta();
      await refreshRemoteBackups();
      
      // If backup succeeded, clear the unsynced changes state
      if (meta != null && meta.status == 'SUCCESS') {
        // Also clear any pending items in SQLite queue as we just did a full backup!
        final pending = await _repository.getPendingSyncQueue();
        for (final item in pending) {
          await _repository.updateSyncQueueStatus(item.id, 'DONE');
        }
        await _repository.clearSyncedQueue();
        await checkUnsyncedStatus();
        state = state.copyWith(isLoading: false);
        return true;
      }
      
      state = state.copyWith(isLoading: false);
      return false;
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
