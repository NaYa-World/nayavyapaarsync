import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'backup_service.dart';
import '../data/repositories/backup_repository.dart';

class SyncQueueService {
  static final SyncQueueService _instance = SyncQueueService._internal();
  factory SyncQueueService() => _instance;
  SyncQueueService._internal();

  final BackupRepository _backupRepository = BackupRepository();
  final BackupService _backupService = BackupService();
  bool _isSyncing = false;

  /// Checks if the device is currently online
  Future<bool> isOnline() async {
    try {
      // Note: connectivity_plus check
      final connectivityResult = await Connectivity().checkConnectivity();
      return !connectivityResult.contains(ConnectivityResult.none) && connectivityResult.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Triggers a sync. If online and there are pending items, performs a backup.
  Future<bool> triggerSync(String deviceId) async {
    if (_isSyncing) return false;
    _isSyncing = true;

    try {
      final hasChanges = await _backupRepository.hasUnsyncedChanges();
      if (!hasChanges) {
        _isSyncing = false;
        return true; // nothing to sync
      }

      final online = await isOnline();
      if (!online) {
        _isSyncing = false;
        return false; // offline, cannot sync now
      }

      // Fetch pending items
      final pendingItems = await _backupRepository.getPendingSyncQueue();
      if (pendingItems.isEmpty) {
        _isSyncing = false;
        return true;
      }

      // Upload database file as the new backup
      final backupMeta = await _backupService.performBackup(deviceId);

      if (backupMeta != null && backupMeta.status == 'SUCCESS') {
        // Mark all processed queue items as DONE
        for (final item in pendingItems) {
          await _backupRepository.updateSyncQueueStatus(item.id, 'DONE');
        }
        // Optional: clear synced items to keep DB compact
        await _backupRepository.clearSyncedQueue();
        
        _isSyncing = false;
        return true;
      } else {
        // Backup failed
        for (final item in pendingItems) {
          await _backupRepository.updateSyncQueueStatus(item.id, 'FAILED');
        }
        _isSyncing = false;
        return false;
      }
    } catch (_) {
      _isSyncing = false;
      return false;
    }
  }
}
