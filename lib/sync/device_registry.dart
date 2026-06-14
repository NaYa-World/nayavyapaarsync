import 'manifest_manager.dart';

class DeviceRegistry {
  /// Verifies if the device is correctly registered in the manifest.
  /// If the registered device ID for the current role does not match,
  /// it replaces the registered device ID, resets its last sync timestamp,
  /// and returns true to trigger a full database restore flow.
  static bool checkAndRegisterDevice(
    Manifest manifest,
    String deviceId,
    String role,
  ) {
    String? oldDeviceId;
    
    // Scan registry for any other device registered under the same role
    for (final entry in manifest.deviceRegistry.entries) {
      if (entry.value.role.toUpperCase() == role.toUpperCase() && entry.key != deviceId) {
        oldDeviceId = entry.key;
        break;
      }
    }

    if (oldDeviceId != null) {
      // Hardware mismatch/replacement detected!
      // Remove old device entry from manifest to prevent stale blocking watermarks
      manifest.deviceRegistry.remove(oldDeviceId);
      
      // Register new device ID with sync timestamp reset to the latest snapshot watermark
      manifest.deviceRegistry[deviceId] = DeviceMeta(
        role: role.toLowerCase(),
        lastSyncedLogTimestamp: manifest.latestSnapshot?.watermarkTimestamp ?? 0,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
      );
      return true; // Needs fresh database restore
    }

    // If device not yet registered, create it
    if (!manifest.deviceRegistry.containsKey(deviceId)) {
      manifest.deviceRegistry[deviceId] = DeviceMeta(
        role: role.toLowerCase(),
        lastSyncedLogTimestamp: manifest.latestSnapshot?.watermarkTimestamp ?? 0,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
      );
      return true; // New device, needs fresh database restore
    } else {
      // Update last seen timestamp for existing device
      final currentMeta = manifest.deviceRegistry[deviceId]!;
      manifest.deviceRegistry[deviceId] = currentMeta.copyWith(
        lastSeen: DateTime.now().millisecondsSinceEpoch,
      );
      return false; // No mismatch, safe to do standard incremental sync
    }
  }
}
