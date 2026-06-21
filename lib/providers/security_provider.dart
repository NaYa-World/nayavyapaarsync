import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'auth_provider.dart';

class SecurityState {
  final bool isBiometricSupported;
  final bool isBiometricEnabled;
  final bool isAppLocked;

  SecurityState({
    required this.isBiometricSupported,
    required this.isBiometricEnabled,
    required this.isAppLocked,
  });

  SecurityState copyWith({
    bool? isBiometricSupported,
    bool? isBiometricEnabled,
    bool? isAppLocked,
  }) {
    return SecurityState(
      isBiometricSupported: isBiometricSupported ?? this.isBiometricSupported,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      isAppLocked: isAppLocked ?? this.isAppLocked,
    );
  }
}

class SecurityNotifier extends StateNotifier<SecurityState> {
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Ref _ref;
  static const String _biometricEnabledKey = 'biometric_enabled';

  SecurityNotifier(this._ref)
      : super(SecurityState(
          isBiometricSupported: false,
          isBiometricEnabled: false,
          isAppLocked: false,
        )) {
    _initSecurity();
  }

  Future<void> _initSecurity() async {
    final bool canCheck = await _auth.canCheckBiometrics;
    final bool isSupported = await _auth.isDeviceSupported();
    final bool isBiometricSupported = canCheck && isSupported;

    String? enabledStr = await _secureStorage.read(key: _biometricEnabledKey);
    bool isBiometricEnabled = enabledStr == 'true';

    // Lock on initial boot if biometrics are enabled and user is signed in
    final userSignedIn = _ref.read(authProvider).user != null;
    final isAppLocked = isBiometricEnabled && userSignedIn;

    state = SecurityState(
      isBiometricSupported: isBiometricSupported,
      isBiometricEnabled: isBiometricEnabled,
      isAppLocked: isAppLocked,
    );
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    await _secureStorage.write(key: _biometricEnabledKey, value: enabled ? 'true' : 'false');
    state = state.copyWith(isBiometricEnabled: enabled);
  }

  void setLocked(bool locked) {
    // Only lock if user is signed in and biometrics are active
    final userSignedIn = _ref.read(authProvider).user != null;
    if (locked && (!state.isBiometricEnabled || !userSignedIn)) return;
    state = state.copyWith(isAppLocked: locked);
  }

  Future<bool> authenticate() async {
    if (!state.isBiometricSupported || !state.isBiometricEnabled) {
      return false;
    }
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Scan fingerprint or face to unlock VyapaarSync',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (authenticated) {
        state = state.copyWith(isAppLocked: false);
      }
      return authenticated;
    } catch (_) {
      return false;
    }
  }

  void forceUnlock() {
    state = state.copyWith(isAppLocked: false);
  }
}

final securityProvider = StateNotifierProvider<SecurityNotifier, SecurityState>((ref) {
  return SecurityNotifier(ref);
});
