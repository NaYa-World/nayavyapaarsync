import 'dart:convert';
import '../services/gdrive_service.dart';

class ManifestSnapshot {
  final String filename;
  final int watermarkTimestamp;
  final String generatedBy;
  final int generatedAt;

  ManifestSnapshot({
    required this.filename,
    required this.watermarkTimestamp,
    required this.generatedBy,
    required this.generatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'filename': filename,
      'watermark_timestamp': watermarkTimestamp,
      'generated_by': generatedBy,
      'generated_at': generatedAt,
    };
  }

  factory ManifestSnapshot.fromMap(Map<String, dynamic> map) {
    return ManifestSnapshot(
      filename: map['filename'] as String,
      watermarkTimestamp: map['watermark_timestamp'] as int,
      generatedBy: map['generated_by'] as String,
      generatedAt: map['generated_at'] as int,
    );
  }
}

class DeviceMeta {
  final String role;
  final int lastSyncedLogTimestamp;
  final int lastSeen;

  DeviceMeta({
    required this.role,
    required this.lastSyncedLogTimestamp,
    required this.lastSeen,
  });

  Map<String, dynamic> toMap() {
    return {
      'role': role,
      'last_synced_log_timestamp': lastSyncedLogTimestamp,
      'last_seen': lastSeen,
    };
  }

  factory DeviceMeta.fromMap(Map<String, dynamic> map) {
    return DeviceMeta(
      role: map['role'] as String,
      lastSyncedLogTimestamp: map['last_synced_log_timestamp'] as int,
      lastSeen: map['last_seen'] as int,
    );
  }

  DeviceMeta copyWith({
    String? role,
    int? lastSyncedLogTimestamp,
    int? lastSeen,
  }) {
    return DeviceMeta(
      role: role ?? this.role,
      lastSyncedLogTimestamp: lastSyncedLogTimestamp ?? this.lastSyncedLogTimestamp,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class Manifest {
  final int schemaVersion;
  final ManifestSnapshot? latestSnapshot;
  final int oldestAvailableLogTimestamp;
  final Map<String, DeviceMeta> deviceRegistry;
  final String? snapshotGenerationClaimedBy;
  final int? snapshotGenerationClaimedAt;

  Manifest({
    this.schemaVersion = 1,
    this.latestSnapshot,
    required this.oldestAvailableLogTimestamp,
    required this.deviceRegistry,
    this.snapshotGenerationClaimedBy,
    this.snapshotGenerationClaimedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'schema_version': schemaVersion,
      'latest_snapshot': latestSnapshot?.toMap(),
      'oldest_available_log_timestamp': oldestAvailableLogTimestamp,
      'device_registry': deviceRegistry.map((k, v) => MapEntry(k, v.toMap())),
      'snapshot_generation_claimed_by': snapshotGenerationClaimedBy,
      'snapshot_generation_claimed_at': snapshotGenerationClaimedAt,
    };
  }

  factory Manifest.fromMap(Map<String, dynamic> map) {
    final registryMap = map['device_registry'] as Map<String, dynamic>? ?? {};
    final registry = registryMap.map(
      (k, v) => MapEntry(k, DeviceMeta.fromMap(Map<String, dynamic>.from(v as Map))),
    );

    return Manifest(
      schemaVersion: map['schema_version'] as int? ?? 1,
      latestSnapshot: map['latest_snapshot'] != null
          ? ManifestSnapshot.fromMap(Map<String, dynamic>.from(map['latest_snapshot'] as Map))
          : null,
      oldestAvailableLogTimestamp: map['oldest_available_log_timestamp'] as int? ?? 0,
      deviceRegistry: registry,
      snapshotGenerationClaimedBy: map['snapshot_generation_claimed_by'] as String?,
      snapshotGenerationClaimedAt: map['snapshot_generation_claimed_at'] as int?,
    );
  }

  Manifest copyWith({
    int? schemaVersion,
    ManifestSnapshot? latestSnapshot,
    int? oldestAvailableLogTimestamp,
    Map<String, DeviceMeta>? deviceRegistry,
    String? snapshotGenerationClaimedBy,
    int? snapshotGenerationClaimedAt,
  }) {
    return Manifest(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      latestSnapshot: latestSnapshot ?? this.latestSnapshot,
      oldestAvailableLogTimestamp: oldestAvailableLogTimestamp ?? this.oldestAvailableLogTimestamp,
      deviceRegistry: deviceRegistry ?? this.deviceRegistry,
      snapshotGenerationClaimedBy: snapshotGenerationClaimedBy ?? this.snapshotGenerationClaimedBy,
      snapshotGenerationClaimedAt: snapshotGenerationClaimedAt ?? this.snapshotGenerationClaimedAt,
    );
  }
}

class ManifestManager {
  final GDriveService _gdriveService = GDriveService();

  /// Downloads and parses the manifest.json file from GDrive.
  /// Returns null if the manifest does not exist or fails to download.
  Future<Manifest?> downloadManifest() async {
    final jsonStr = await _gdriveService.downloadManifest();
    if (jsonStr == null || jsonStr.trim().isEmpty) return null;

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return Manifest.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  /// Serialises and uploads the manifest object to GDrive.
  Future<bool> uploadManifest(Manifest manifest) async {
    final jsonStr = jsonEncode(manifest.toMap());
    return await _gdriveService.uploadManifest(jsonStr);
  }
}
