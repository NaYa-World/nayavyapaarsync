import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:uuid/uuid.dart';
import '../services/auth_service.dart';

class AuthState {
  final GoogleSignInAccount? user;
  final bool isLoading;
  final String? errorMessage;
  final String deviceId;

  AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
    required this.deviceId,
  });

  AuthState copyWith({
    GoogleSignInAccount? user,
    bool? isLoading,
    String? errorMessage,
    String? deviceId,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage, // clears if not provided
      deviceId: deviceId ?? this.deviceId,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService = AuthService();
  final _secureStorage = const FlutterSecureStorage();
  static const String _deviceIdKey = 'device_unique_id';

  AuthNotifier() : super(AuthState(deviceId: 'unknown')) {
    _initAuth();
  }

  Future<void> _initAuth() async {
    state = state.copyWith(isLoading: true);

    // 1. Get or generate persistent Device ID
    String? deviceId = await _secureStorage.read(key: _deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _secureStorage.write(key: _deviceIdKey, value: deviceId);
    }

    state = state.copyWith(deviceId: deviceId);

    // 2. Silent login check
    final user = await _authService.signInSilently();
    state = state.copyWith(user: user, isLoading: false);
  }

  /// Triggers standard Google Sign-In
  Future<bool> signIn() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await _authService.signIn();
      if (user != null) {
        state = state.copyWith(user: user, isLoading: false);
        return true;
      } else {
        state = state.copyWith(isLoading: false, errorMessage: 'Sign-in cancelled');
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sign-in failed: ${e.toString()}',
      );
      return false;
    }
  }

  /// Logs out of Google
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authService.signOut();
      state = state.copyWith(user: null, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Logout failed: ${e.toString()}',
      );
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
