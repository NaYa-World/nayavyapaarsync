import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/payment.dart';
import '../database/db_helper.dart';
import '../../core/utils/fy_guard.dart';

class PaymentRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Fetches all active payments
  Future<List<Payment>> getPayments({String companyId = 'company_default'}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'is_deleted = 0 AND company_id = ?',
      whereArgs: [companyId],
      orderBy: 'date DESC, created_at DESC',
    );
    return List.generate(maps.length, (i) => Payment.fromMap(maps[i]));
  }

  /// Fetches payments associated with a specific party
  Future<List<Payment>> getPaymentsForParty(String partyId, {String companyId = 'company_default'}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'party_id = ? AND is_deleted = 0 AND company_id = ?',
      whereArgs: [partyId, companyId],
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
  Future<void> insertPayment(Payment payment, String deviceId, {String companyId = 'company_default'}) async {
    await FyGuard.checkDate(date: payment.date);
    final db = await _dbHelper.database;
    final map = payment.toMap();
    map['company_id'] = companyId;

    await db.transaction((txn) async {
      await txn.insert('payments', map);

      // Audit Log
      await _dbHelper.insertAuditLog(
        txn,
        id: _uuid.v4(),
        tableName: 'payments',
        recordId: payment.id,
        action: 'CREATE',
        oldValues: null,
        newValues: jsonEncode(map),
        timestamp: DateTime.now().toIso8601String(),
        deviceId: deviceId,
      );

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
  Future<void> updatePayment(Payment payment, String deviceId, {String companyId = 'company_default'}) async {
    final db = await _dbHelper.database;
    final currentPayment = await getPayment(payment.id);
    if (currentPayment == null) return;
    await FyGuard.checkDate(date: currentPayment.date);
    await FyGuard.checkDate(date: payment.date);
    final map = payment.toMap();
    map['company_id'] = companyId;

    await db.transaction((txn) async {
      await txn.update(
        'payments',
        map,
        where: 'id = ?',
        whereArgs: [payment.id],
      );

      // Audit Log
      await _dbHelper.insertAuditLog(
        txn,
        id: _uuid.v4(),
        tableName: 'payments',
        recordId: payment.id,
        action: 'EDIT',
        oldValues: jsonEncode(currentPayment.toMap()),
        newValues: jsonEncode(map),
        timestamp: DateTime.now().toIso8601String(),
        deviceId: deviceId,
      );

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
      await _dbHelper.insertAuditLog(
        txn,
        id: _uuid.v4(),
        tableName: 'payments',
        recordId: id,
        action: 'DELETE',
        oldValues: jsonEncode(currentPayment.toMap()),
        newValues: jsonEncode(updatedMap),
        timestamp: DateTime.now().toIso8601String(),
        deviceId: deviceId,
      );

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
