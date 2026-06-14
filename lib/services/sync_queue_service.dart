import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database/db_helper.dart';
import '../data/repositories/backup_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../sync/manifest_manager.dart';
import '../sync/device_registry.dart';
import '../sync/snapshot_coordinator.dart';
import '../sync/log_pruner.dart';
import '../sync/sync_applier.dart';
import 'gdrive_service.dart';

class SyncQueueService {
  static final SyncQueueService _instance = SyncQueueService._internal();
  factory SyncQueueService() => _instance;
  SyncQueueService._internal();

  bool _isSyncing = false;

  /// Checks if the device is currently online
  Future<bool> isOnline() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return !connectivityResult.contains(ConnectivityResult.none) && connectivityResult.isNotEmpty;
    } catch (e, stack) {
      debugPrint('Error checking connectivity: $e\n$stack');
      return false;
    }
  }

  /// Triggers an incremental sync with Google Drive.
  /// Returns true if any remote changes were applied (requiring a local UI refresh).
  Future<bool> triggerSync(String deviceId) async {
    if (_isSyncing) return false;

    final online = await isOnline();
    if (!online) return false;

    _isSyncing = true;

    try {
      final db = await DbHelper().database;
      final settings = await SettingsRepository().getSettings();
      if (!settings.isValid) {
        _isSyncing = false;
        return false;
      }

      final role = settings.role;

      // 1. Download manifest.json
      final manifestManager = ManifestManager();
      var manifest = await manifestManager.downloadManifest();

      if (manifest == null) {
        // First-ever initialization: create empty manifest on Google Drive
        manifest = Manifest(
          oldestAvailableLogTimestamp: DateTime.now().millisecondsSinceEpoch,
          deviceRegistry: {},
        );
        await manifestManager.uploadManifest(manifest);
      }

      // 2. Check registry and register device
      final needsRestore = DeviceRegistry.checkAndRegisterDevice(manifest, deviceId, role);
      if (needsRestore) {
        // Trigger a fresh restore flow (snapshot + logs)
        final restored = await restoreFromManifest(manifest, deviceId, role);
        _isSyncing = false;
        return restored;
      }

      // 3. Download and apply remote logs
      bool hasChangesApplied = await downloadAndApplyRemoteLogs(db, manifest, deviceId);

      // 4. Upload local pending logs
      await uploadLocalPendingLogs(db, manifest, deviceId);

      // 5. Update last seen and sync status in manifest, then upload
      final currentMeta = manifest.deviceRegistry[deviceId]!;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      manifest.deviceRegistry[deviceId] = currentMeta.copyWith(
        lastSeen: nowMs,
      );
      await manifestManager.uploadManifest(manifest);

      // 6. Check if snapshot generation is needed
      final coordinator = SnapshotCoordinator();
      final needsSnapshot = await coordinator.shouldIGenerateSnapshot(manifest);
      if (needsSnapshot) {
        final claimed = await coordinator.claimSnapshotGeneration(deviceId);
        if (claimed) {
          // Generate, upload snapshot, update manifest snapshot pointer, and prune
          await generateAndUploadSnapshot(db, manifest, deviceId);
          await coordinator.releaseClaim(deviceId);
        }
      }

      _isSyncing = false;
      return hasChangesApplied;
    } catch (e, stack) {
      debugPrint('Error during triggerSync: $e\n$stack');
      _isSyncing = false;
      return false;
    }
  }

  /// Performs a full restore on a new device or when a hardware ID mismatch is corrected.
  Future<bool> restoreFromManifest(
    Manifest manifest,
    String deviceId,
    String role,
  ) async {
    try {
      final dbHelper = DbHelper();
      int watermark = 0;

      if (manifest.latestSnapshot != null) {
        final snapshotFilename = manifest.latestSnapshot!.filename;
        
        // Find snapshot file ID on Google Drive
        final snapshots = await GDriveService().listSnapshots();
        final snapshotMeta = snapshots.firstWhere(
          (s) => s.name == snapshotFilename,
          orElse: () => throw Exception('Snapshot not found on Drive'),
        );

        // Close connection before writing snapshot file over local database
        await dbHelper.close();
        final String dbPath = join(await getDatabasesPath(), 'godown_management.db');
        final File localDbFile = File(dbPath);

        final success = await GDriveService().downloadBackup(snapshotMeta.id, localDbFile);
        if (!success) {
          throw Exception('Failed to download snapshot file');
        }

        watermark = manifest.latestSnapshot!.watermarkTimestamp;
      }

      // Reopen connection
      final db = await dbHelper.database;

      // Download and apply all logs where timestamp > watermark
      final logs = await GDriveService().listLogs();
      final eligibleLogs = logs.where((log) {
        final timestamp = LogPruner().getLogTimestamp(log.name);
        return timestamp != null && timestamp > watermark;
      }).toList();

      // Sort logs by timestamp ascending
      eligibleLogs.sort((a, b) {
        final tsA = LogPruner().getLogTimestamp(a.name) ?? 0;
        final tsB = LogPruner().getLogTimestamp(b.name) ?? 0;
        return tsA.compareTo(tsB);
      });

      int maxAppliedTimestamp = watermark;

      for (final log in eligibleLogs) {
        final logContent = await GDriveService().downloadLog(log.id);
        if (logContent != null) {
          final List<dynamic> itemsList = jsonDecode(logContent) as List<dynamic>;
          for (final item in itemsList) {
            final itemMap = Map<String, dynamic>.from(item as Map);
            final operation = itemMap['operation'] as String;
            final tableName = itemMap['table_name'] as String;
            final recordId = itemMap['record_id'] as String;
            final fieldName = itemMap['field_name'] as String? ?? '_full_row';
            final newValue = itemMap['new_value'] as String?;
            final isResolution = (itemMap['is_resolution'] as int? ?? 0) == 1;

            if (isResolution) {
              if (newValue != null) {
                await db.update(
                  tableName,
                  {fieldName: newValue},
                  where: 'id = ?',
                  whereArgs: [recordId],
                );
              }
            } else if (fieldName == '_full_row') {
              final payload = itemMap['payload'] != null
                  ? jsonDecode(itemMap['payload'] as String) as Map<String, dynamic>
                  : <String, dynamic>{};
              await SyncApplier.applySyncItem(db, operation, tableName, recordId, payload);
            } else if (operation == 'CREATE' || operation == 'DELETE') {
              final payload = itemMap['payload'] != null
                  ? jsonDecode(itemMap['payload'] as String) as Map<String, dynamic>
                  : <String, dynamic>{};
              await SyncApplier.applySyncItem(db, operation, tableName, recordId, payload);
            } else {
              // Field-level EDIT
              if (newValue != null) {
                await db.update(
                  tableName,
                  {fieldName: newValue},
                  where: 'id = ?',
                  whereArgs: [recordId],
                );
              }
            }
          }
          final logTs = LogPruner().getLogTimestamp(log.name) ?? watermark;
          if (logTs > maxAppliedTimestamp) {
            maxAppliedTimestamp = logTs;
          }
        }
      }

      // Register device with correct watermark
      manifest.deviceRegistry[deviceId] = DeviceMeta(
        role: role.toLowerCase(),
        lastSyncedLogTimestamp: maxAppliedTimestamp,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
      );
      await ManifestManager().uploadManifest(manifest);

      return true;
    } catch (e, stack) {
      debugPrint('Error during restoreFromManifest: $e\n$stack');
      return false;
    }
  }

  /// Downloads and applies remote changes that this device has not synced yet.
  Future<bool> downloadAndApplyRemoteLogs(
    Database db,
    Manifest manifest,
    String deviceId,
  ) async {
    final currentMeta = manifest.deviceRegistry[deviceId];
    if (currentMeta == null) return false;

    final lastSynced = currentMeta.lastSyncedLogTimestamp;
    final logs = await GDriveService().listLogs();

    final remoteLogs = logs.where((log) {
      final logDeviceId = getLogDeviceId(log.name);
      final logTimestamp = LogPruner().getLogTimestamp(log.name);
      return logDeviceId != null &&
          logDeviceId != deviceId &&
          logTimestamp != null &&
          logTimestamp > lastSynced;
    }).toList();

    if (remoteLogs.isEmpty) return false;

    // Sort logs ascending by timestamp
    remoteLogs.sort((a, b) {
      final tsA = LogPruner().getLogTimestamp(a.name) ?? 0;
      final tsB = LogPruner().getLogTimestamp(b.name) ?? 0;
      return tsA.compareTo(tsB);
    });

    int maxAppliedTimestamp = lastSynced;
    bool anyApplied = false;

    for (final log in remoteLogs) {
      final logContent = await GDriveService().downloadLog(log.id);
      if (logContent != null) {
        final List<dynamic> itemsList = jsonDecode(logContent) as List<dynamic>;

        await db.transaction((txn) async {
          for (final item in itemsList) {
            final itemMap = Map<String, dynamic>.from(item as Map);
            await SyncApplier.applyRemoteChange(txn, itemMap);
          }
        });

        anyApplied = true;
        final logTs = LogPruner().getLogTimestamp(log.name) ?? lastSynced;
        if (logTs > maxAppliedTimestamp) {
          maxAppliedTimestamp = logTs;
        }
      }
    }

    // Update watermark in manifest state
    manifest.deviceRegistry[deviceId] = currentMeta.copyWith(
      lastSyncedLogTimestamp: maxAppliedTimestamp,
    );

    return anyApplied;
  }

  /// Uploads local pending logs from SQLite sync_queue to GDrive
  Future<bool> uploadLocalPendingLogs(
    Database db,
    Manifest manifest,
    String deviceId,
  ) async {
    final backupRepository = BackupRepository();
    final pendingItems = await backupRepository.getPendingSyncQueue();
    if (pendingItems.isEmpty) return false;

    final now = DateTime.now();
    final secondsSinceEpoch = now.millisecondsSinceEpoch ~/ 1000;
    final logFileName = 'sync_log_${deviceId}_$secondsSinceEpoch.json';

    // Serialise queue items
    final List<Map<String, dynamic>> itemsList = pendingItems.map((e) => e.toMap()).toList();
    final jsonStr = jsonEncode(itemsList);

    // Upload to Google Drive logs folder
    final uploadSuccess = await GDriveService().uploadLog(logFileName, jsonStr);
    if (uploadSuccess == null) {
      return false; // failed upload
    }

    // Mark processed items as DONE
    for (final item in pendingItems) {
      await backupRepository.updateSyncQueueStatus(item.id, 'DONE');
    }
    await backupRepository.clearSyncedQueue();

    // Update sync watermark in manifest state
    final currentMeta = manifest.deviceRegistry[deviceId]!;
    manifest.deviceRegistry[deviceId] = currentMeta.copyWith(
      lastSyncedLogTimestamp: now.millisecondsSinceEpoch,
    );

    return true;
  }

  /// Generates and uploads a database snapshot to Google Drive snapshots folder
  Future<void> generateAndUploadSnapshot(
    Database db,
    Manifest manifest,
    String deviceId,
  ) async {
    try {
      final String dbPath = join(await getDatabasesPath(), 'godown_management.db');
      final File dbFile = File(dbPath);

      final now = DateTime.now();
      final secondsSinceEpoch = now.millisecondsSinceEpoch ~/ 1000;

      final year = now.year;
      final month = now.month.toString().padLeft(2, '0');
      final day = now.day.toString().padLeft(2, '0');
      final snapshotFileName = 'godown_snapshot_$year-$month-${day}_T$secondsSinceEpoch.db';

      // Perform GDrive upload
      final snapshotId = await GDriveService().uploadSnapshot(dbFile, snapshotFileName);
      if (snapshotId == null) return;

      // Find the maximum lastSyncedLogTimestamp across all devices in the registry
      int watermark = 0;
      for (final device in manifest.deviceRegistry.values) {
        if (device.lastSyncedLogTimestamp > watermark) {
          watermark = device.lastSyncedLogTimestamp;
        }
      }

      if (watermark == 0) {
        watermark = now.millisecondsSinceEpoch;
      }

      // Update manifest latest snapshot
      final updatedManifest = manifest.copyWith(
        latestSnapshot: ManifestSnapshot(
          filename: snapshotFileName,
          watermarkTimestamp: watermark,
          generatedBy: deviceId,
          generatedAt: now.millisecondsSinceEpoch,
        ),
      );

      final manifestManager = ManifestManager();
      await manifestManager.uploadManifest(updatedManifest);

      // Run safe pruning (only snapshot generator does this!)
      await LogPruner().prune(updatedManifest);
    } catch (e, stack) {
      debugPrint('Error during generateAndUploadSnapshot: $e\n$stack');
    }
  }

  /// Helper to extract device ID from log filename
  String? getLogDeviceId(String filename) {
    final nameWithoutExt = filename.replaceFirst('.json', '');
    final parts = nameWithoutExt.split('_');
    if (parts.length < 4) return null;
    return parts.sublist(2, parts.length - 1).join('_');
  }
}
