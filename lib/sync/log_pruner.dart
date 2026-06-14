import '../services/gdrive_service.dart';
import 'manifest_manager.dart';

class LogPruner {
  final GDriveService _gdriveService = GDriveService();

  /// Prunes remote change logs and snapshots according to retention rules.
  /// Called only by the device that generated and uploaded a new snapshot.
  Future<void> prune(Manifest manifest) async {
    await pruneLogs(manifest);
    await pruneSnapshots(manifest);
  }

  /// Deletes logs older than the minimum sync timestamp across all active devices.
  /// Never deletes logs newer than 30 days ago.
  Future<void> pruneLogs(Manifest manifest) async {
    try {
      if (manifest.deviceRegistry.isEmpty) return;

      // 1. Find the minimum lastSyncedLogTimestamp across all devices in the registry
      int minTimestamp = -1;
      for (final device in manifest.deviceRegistry.values) {
        if (minTimestamp == -1 || device.lastSyncedLogTimestamp < minTimestamp) {
          minTimestamp = device.lastSyncedLogTimestamp;
        }
      }

      if (minTimestamp == -1) return;

      // 2. Fetch all log files from Google Drive
      final logs = await _gdriveService.listLogs();

      // 3. Define the 30-day cutoff timestamp (logs newer than this must be preserved)
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      final cutoffTimestamp = cutoffDate.millisecondsSinceEpoch;

      // 4. Delete eligible log files
      for (final log in logs) {
        final logTimestamp = getLogTimestamp(log.name);
        if (logTimestamp != null) {
          // Rule: Delete if older than min device watermark AND older than 30 days
          if (logTimestamp < minTimestamp && logTimestamp < cutoffTimestamp) {
            await _gdriveService.deleteFile(log.id);
          }
        }
      }
    } catch (_) {
      // Fail-silent for background pruning tasks
    }
  }

  /// Retains only the last 3 snapshots in snapshots/ folder.
  Future<void> pruneSnapshots(Manifest manifest) async {
    try {
      final snapshots = await _gdriveService.listSnapshots();
      if (snapshots.length <= 3) return;

      // Sort snapshots by created time descending (newest first)
      // Note: listSnapshots already returns ordered desc, but we sort to be certain
      snapshots.sort((a, b) => b.createdTime.compareTo(a.createdTime));

      // Delete everything after index 2 (retaining index 0, 1, 2)
      for (int i = 3; i < snapshots.length; i++) {
        await _gdriveService.deleteFile(snapshots[i].id);
      }
    } catch (_) {
      // Fail-silent
    }
  }

  /// Helper to extract timestamp from log filename: sync_log_<device_id>_<seconds_since_epoch>.json
  int? getLogTimestamp(String filename) {
    final nameWithoutExt = filename.replaceFirst('.json', '');
    final parts = nameWithoutExt.split('_');
    if (parts.length < 4) return null;
    final timestampStr = parts.last;
    final seconds = int.tryParse(timestampStr);
    if (seconds == null) return null;
    return seconds * 1000; // Returns milliseconds since epoch
  }
}
