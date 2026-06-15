import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/expense.dart';
import '../database/db_helper.dart';
import '../../core/utils/fy_guard.dart';

class ExpenseRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Fetches all active expenses
  Future<List<Expense>> getExpenses() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'expenses',
      where: 'is_deleted = 0',
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => Expense.fromMap(maps[i]));
  }

  /// Fetches a specific expense by ID
  Future<Expense?> getExpense(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Expense.fromMap(maps.first);
  }

  /// Inserts a new expense, writes to AuditLog and SyncQueue in a txn
  Future<void> insertExpense(Expense expense, String deviceId) async {
    await FyGuard.checkDate(date: expense.date);
    final db = await _dbHelper.database;
    final map = expense.toMap();

    await db.transaction((txn) async {
      await txn.insert('expenses', map);

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'expenses',
        'record_id': expense.id,
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
        'table_name': 'expenses',
        'record_id': expense.id,
        'payload': jsonEncode(map),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Updates an expense, writes to AuditLog and SyncQueue in a txn
  Future<void> updateExpense(Expense expense, String deviceId) async {
    final db = await _dbHelper.database;
    final currentExpense = await getExpense(expense.id);
    if (currentExpense == null) return;
    await FyGuard.checkDate(date: currentExpense.date);
    await FyGuard.checkDate(date: expense.date);
    final map = expense.toMap();

    await db.transaction((txn) async {
      await txn.update(
        'expenses',
        map,
        where: 'id = ?',
        whereArgs: [expense.id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'expenses',
        'record_id': expense.id,
        'action': 'EDIT',
        'old_values': jsonEncode(currentExpense.toMap()),
        'new_values': jsonEncode(map),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'EDIT',
        'table_name': 'expenses',
        'record_id': expense.id,
        'payload': jsonEncode(map),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Soft deletes an expense
  Future<void> deleteExpense(String id, String deviceId) async {
    final db = await _dbHelper.database;
    final currentExpense = await getExpense(id);
    if (currentExpense == null) return;
    await FyGuard.checkDate(date: currentExpense.date);

    final updatedMap = currentExpense.copyWith(isDeleted: true).toMap();

    await db.transaction((txn) async {
      await txn.update(
        'expenses',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'expenses',
        'record_id': id,
        'action': 'DELETE',
        'old_values': jsonEncode(currentExpense.toMap()),
        'new_values': jsonEncode(updatedMap),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'DELETE',
        'table_name': 'expenses',
        'record_id': id,
        'payload': jsonEncode(updatedMap),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }
}
