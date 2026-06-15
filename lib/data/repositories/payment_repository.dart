import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/payment.dart';
import '../database/db_helper.dart';
import '../../core/utils/fy_guard.dart';

class PaymentRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Fetches all active payments
  Future<List<Payment>> getPayments() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'is_deleted = 0',
      orderBy: 'date DESC, created_at DESC',
    );
    return List.generate(maps.length, (i) => Payment.fromMap(maps[i]));
  }

  /// Fetches payments associated with a specific party
  Future<List<Payment>> getPaymentsForParty(String partyId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'party_id = ? AND is_deleted = 0',
      whereArgs: [partyId],
      orderBy: 'date DESC, created_at DESC',
    );
    return List.generate(maps.length, (i) => Payment.fromMap(maps[i]));
  }

  /// Fetches a specific payment by ID
  Future<Payment?> getPayment(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Payment.fromMap(maps.first);
  }

  /// Inserts a new payment transaction
  Future<void> insertPayment(Payment payment, String deviceId) async {
    await FyGuard.checkDate(date: payment.date);
    final db = await _dbHelper.database;
    final map = payment.toMap();

    await db.transaction((txn) async {
      await txn.insert('payments', map);

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'payments',
        'record_id': payment.id,
        'action': 'CREATE',
        'old_values': null,
        'new_values': jsonEncode(map),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'CREATE',
        'table_name': 'payments',
        'record_id': payment.id,
        'payload': jsonEncode(map),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Updates a payment transaction
  Future<void> updatePayment(Payment payment, String deviceId) async {
    final db = await _dbHelper.database;
    final currentPayment = await getPayment(payment.id);
    if (currentPayment == null) return;
    await FyGuard.checkDate(date: currentPayment.date);
    await FyGuard.checkDate(date: payment.date);
    final map = payment.toMap();

    await db.transaction((txn) async {
      await txn.update(
        'payments',
        map,
        where: 'id = ?',
        whereArgs: [payment.id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'payments',
        'record_id': payment.id,
        'action': 'EDIT',
        'old_values': jsonEncode(currentPayment.toMap()),
        'new_values': jsonEncode(map),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'EDIT',
        'table_name': 'payments',
        'record_id': payment.id,
        'payload': jsonEncode(map),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Soft deletes a payment transaction
  Future<void> deletePayment(String id, String deviceId) async {
    final db = await _dbHelper.database;
    final currentPayment = await getPayment(id);
    if (currentPayment == null) return;
    await FyGuard.checkDate(date: currentPayment.date);

    final updatedMap = currentPayment.copyWith(isDeleted: true).toMap();

    await db.transaction((txn) async {
      await txn.update(
        'payments',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'payments',
        'record_id': id,
        'action': 'DELETE',
        'old_values': jsonEncode(currentPayment.toMap()),
        'new_values': jsonEncode(updatedMap),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'DELETE',
        'table_name': 'payments',
        'record_id': id,
        'payload': jsonEncode(updatedMap),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }
}
