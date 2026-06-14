import 'manifest_manager.dart';

class SnapshotCoordinator {
  final ManifestManager _manifestManager = ManifestManager();

  /// Determines whether a new snapshot should be generated.
  /// True if there is no existing snapshot or if the latest snapshot is older than 24 hours.
  Future<bool> shouldIGenerateSnapshot(Manifest manifest) async {
    final latestSnapshot = manifest.latestSnapshot;
    if (latestSnapshot == null) return true;

    final snapshotAge = DateTime.now().millisecondsSinceEpoch - latestSnapshot.generatedAt;
    if (snapshotAge < const Duration(hours: 24).inMilliseconds) {
      return false;
    }

    return true;
  }

  /// Attempts to claim the snapshot generation responsibility on the central manifest.json.
  /// Returns true if the claim was successfully written/acquired.
  /// Returns false if another device holds a valid lock claimed within the last 5 minutes.
  Future<bool> claimSnapshotGeneration(String deviceId) async {
    // 1. Read manifest again immediately before writing to achieve optimistic lock check
    final manifest = await _manifestManager.downloadManifest();
    if (manifest == null) {
      return false; // Can't claim if manifest is unavailable
    }

    // 2. If someone else claimed in the last 5 minutes, stand down
    final claimedBy = manifest.snapshotGenerationClaimedBy;
    final claimedAt = manifest.snapshotGenerationClaimedAt;
    
    if (claimedBy != null &&
        claimedBy != deviceId &&
        claimedAt != null &&
        claimedAt > DateTime.now().millisecondsSinceEpoch - const Duration(minutes: 5).inMilliseconds) {
      return false; // Already locked by another device
    }

    // 3. Write our claim to manifest
    final updatedManifest = manifest.copyWith(
      snapshotGenerationClaimedBy: deviceId,
      snapshotGenerationClaimedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final success = await _manifestManager.uploadManifest(updatedManifest);
    return success;
  }

  /// Clears the claim lock in the manifest once snapshot generation is complete or fails
  Future<void> releaseClaim(String deviceId) async {
    final manifest = await _manifestManager.downloadManifest();
    if (manifest == null) return;

    if (manifest.snapshotGenerationClaimedBy == deviceId) {
      final updatedManifest = manifest.copyWith(
        snapshotGenerationClaimedBy: null,
        snapshotGenerationClaimedAt: null,
      );
      await _manifestManager.uploadManifest(updatedManifest);
    }
  }
}
