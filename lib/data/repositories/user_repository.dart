import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../models/app_user.dart';
import '../database/db_helper.dart';

class UserRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Legacy SHA-256 hash of a plain-text PIN (unsalted)
  static String hashPinLegacy(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  /// Salted & key-stretched hashing (1000 iterations of SHA-256)
  static String hashPinSecure(String pin, String salt) {
    var input = pin + salt;
    for (int i = 0; i < 1000; i++) {
      final bytes = utf8.encode(input);
      input = sha256.convert(bytes).toString();
    }
    return input;
  }

  /// Backwards-compatible SHA-256 hash
  static String hashPin(String pin) {
    return hashPinLegacy(pin);
  }

  /// Helper to generate a random salt
  static String generateSalt() {
    return const Uuid().v4();
  }

  /// Validates a PIN against stored hash
  bool validatePin(String pin, String storedHash, {String? salt}) {
    if (salt != null && salt.isNotEmpty) {
      return hashPinSecure(pin, salt) == storedHash;
    }
    return hashPinLegacy(pin) == storedHash;
  }

  Future<List<AppUser>> getUsers({bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'app_users',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name ASC',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  Future<AppUser?> getUserById(String id) async {
    final db = await _dbHelper.database;
    final rows =
        await db.query('app_users', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  /// Creates a new user with a plain-text PIN (hashed securely with salt)
  Future<AppUser> createUser({
    required String name,
    required String plainPin,
    required String role,
    String? companyId,
    required String deviceId,
  }) async {
    final db = await _dbHelper.database;
    final salt = generateSalt();
    final user = AppUser(
      id: _uuid.v4(),
      name: name,
      pinHash: hashPinSecure(plainPin, salt),
      salt: salt,
      role: role,
      companyId: companyId,
      createdAt: DateTime.now(),
    );
    await db.transaction((txn) async {
      await txn.insert('app_users', user.toMap());
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'app_users',
        'record_id': user.id,
        'action': 'CREATE',
        'old_values': null,
        'new_values': jsonEncode({
          'name': user.name,
          'role': user.role,
          'company_id': user.companyId,
        }),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });
    });
    return user;
  }

  /// Updates a user's role (PIN change is a separate method)
  Future<void> updateUserRole(
      String userId, String newRole, String deviceId) async {
    final db = await _dbHelper.database;
    final existing = await getUserById(userId);
    if (existing == null) return;
    await db.transaction((txn) async {
      await txn.update(
        'app_users',
        {'role': newRole},
        where: 'id = ?',
        whereArgs: [userId],
      );
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'app_users',
        'record_id': userId,
        'action': 'EDIT',
        'old_values': jsonEncode({'role': existing.role}),
        'new_values': jsonEncode({'role': newRole}),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });
    });
  }

  /// Changes a user's PIN securely generating a new salt
  Future<void> changePin(
      String userId, String newPlainPin, String deviceId) async {
    final db = await _dbHelper.database;
    final newSalt = generateSalt();
    final newHash = hashPinSecure(newPlainPin, newSalt);
    await db.transaction((txn) async {
      await txn.update(
        'app_users',
        {
          'pin_hash': newHash,
          'salt': newSalt,
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'app_users',
        'record_id': userId,
        'action': 'EDIT',
        'old_values': jsonEncode({'pin_hash': '***'}),
        'new_values': jsonEncode({'pin_hash': '***changed***'}),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });
    });
  }

  /// Soft-deletes a user
  Future<void> deactivateUser(String userId, String deviceId) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        'app_users',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [userId],
      );
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'app_users',
        'record_id': userId,
        'action': 'DELETE',
        'old_values': null,
        'new_values': null,
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });
    });
  }
}
