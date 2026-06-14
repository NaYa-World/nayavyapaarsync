import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'manifest_manager.dart';

class RoleNotInitializedException implements Exception {
  final String message;
  RoleNotInitializedException(this.message);
  @override
  String toString() => message;
}

class SyncRoleManager {
  static final SyncRoleManager _instance = SyncRoleManager._internal();
  factory SyncRoleManager() => _instance;
  SyncRoleManager._internal();

  final _secureStorage = const FlutterSecureStorage();
  String? _cachedRole;

  /// Loads cached role from secure storage at app boot as a fallback.
  Future<void> initAtBoot() async {
    _cachedRole = await _secureStorage.read(key: 'cached_role');
  }

  /// Updates the cached role from the Drive manifest registry.
  /// This is the source of truth, called during every sync.
  Future<void> updateFromManifest(Manifest manifest, String deviceId) async {
    final deviceMeta = manifest.deviceRegistry[deviceId];
    if (deviceMeta != null) {
      _cachedRole = deviceMeta.role.toUpperCase();
      await _secureStorage.write(key: 'cached_role', value: _cachedRole);
    }
  }

  /// Returns the current active role ('OWNER' or 'ACCOUNTANT').
  /// Throws RoleNotInitializedException if called before initialization.
  String get currentRole {
    if (_cachedRole != null) {
      return _cachedRole!;
    }
    throw RoleNotInitializedException(
      'SyncRoleManager role not initialized. Trigger sync or set profile settings first.'
    );
  }

  /// Sets role manually, used when the profile settings are first saved.
  Future<void> setRoleManually(String role) async {
    _cachedRole = role.toUpperCase();
    await _secureStorage.write(key: 'cached_role', value: _cachedRole);
  }

  /// Clears the cached role, used on logout.
  Future<void> clearRole() async {
    _cachedRole = null;
    await _secureStorage.delete(key: 'cached_role');
  }
}
