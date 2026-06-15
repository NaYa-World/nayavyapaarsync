import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/db_helper.dart';
import '../data/models/app_user.dart';
import '../data/repositories/user_repository.dart';

// ─── Repository Provider ────────────────────────────────────────────────────

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

// ─── Users List ──────────────────────────────────────────────────────────────

class UserNotifier extends StateNotifier<AsyncValue<List<AppUser>>> {
  final UserRepository _repo;

  UserNotifier(this._repo) : super(const AsyncValue.loading()) {
    loadUsers();
  }

  Future<void> loadUsers() async {
    try {
      state = const AsyncValue.loading();
      final users = await _repo.getUsers();
      state = AsyncValue.data(users);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<AppUser?> createUser({
    required String name,
    required String plainPin,
    required String role,
    String? companyId,
  }) async {
    try {
      final user = await _repo.createUser(
        name: name,
        plainPin: plainPin,
        role: role,
        companyId: companyId,
        deviceId: 'local',
      );
      await loadUsers();
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateRole(String userId, String newRole) async {
    await _repo.updateUserRole(userId, newRole, 'local');
    await loadUsers();
  }

  Future<void> changePin(String userId, String newPin) async {
    await _repo.changePin(userId, newPin, 'local');
  }

  Future<void> deactivateUser(String userId) async {
    await _repo.deactivateUser(userId, 'local');
    await loadUsers();
  }

  /// Validates a PIN for a given user ID. Returns the user if valid, else null.
  /// Silently upgrades legacy unsalted user PINs to salted key-stretched hashes on successful login.
  Future<AppUser?> authenticate(String userId, String plainPin) async {
    final user = await _repo.getUserById(userId);
    if (user == null) return null;
    final isValid = _repo.validatePin(plainPin, user.pinHash, salt: user.salt);
    if (!isValid) return null;

    if (user.salt == null || user.salt!.isEmpty) {
      final newSalt = UserRepository.generateSalt();
      final newHash = UserRepository.hashPinSecure(plainPin, newSalt);
      final formattedHash = '$newSalt:$newHash';
      final db = await DbHelper().database;
      await db.update(
        'app_users',
        {
          'pin_hash': formattedHash,
          'salt': newSalt,
        },
        where: 'id = ?',
        whereArgs: [user.id],
      );
      return user.copyWith(pinHash: formattedHash, salt: newSalt);
    }
    return user;
  }
}

final userProvider =
    StateNotifierProvider<UserNotifier, AsyncValue<List<AppUser>>>((ref) {
  final repo = ref.watch(userRepositoryProvider);
  return UserNotifier(repo);
});
