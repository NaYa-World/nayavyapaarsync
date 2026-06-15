import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/company.dart';
import '../models/financial_year.dart';
import '../database/db_helper.dart';

class CompanyRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  // ─── Companies ───────────────────────────────────────────────────────────

  Future<List<Company>> getCompanies() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'companies',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
    return rows.map(Company.fromMap).toList();
  }

  Future<Company?> getCompanyById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('companies', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Company.fromMap(rows.first);
  }

  Future<void> saveCompany(Company company, String deviceId) async {
    final db = await _dbHelper.database;
    final existing = await getCompanyById(company.id);
    await db.transaction((txn) async {
      await txn.insert(
        'companies',
        company.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'companies',
        'record_id': company.id,
        'action': existing == null ? 'CREATE' : 'EDIT',
        'old_values': existing != null ? jsonEncode(existing.toMap()) : null,
        'new_values': jsonEncode(company.toMap()),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });
    });
  }

  Future<void> deleteCompany(String id, String deviceId) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        'companies',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'companies',
        'record_id': id,
        'action': 'DELETE',
        'old_values': null,
        'new_values': null,
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });
    });
  }

  // ─── Financial Years ──────────────────────────────────────────────────────

  Future<List<FinancialYear>> getFinancialYears(String companyId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'financial_years',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'start_date DESC',
    );
    return rows.map(FinancialYear.fromMap).toList();
  }

  Future<FinancialYear?> getFinancialYearForDate(
      String companyId, DateTime date) async {
    final db = await _dbHelper.database;
    final dateStr = date.toIso8601String().substring(0, 10);
    final rows = await db.query(
      'financial_years',
      where:
          'company_id = ? AND start_date <= ? AND end_date >= ?',
      whereArgs: [companyId, dateStr, dateStr],
    );
    if (rows.isEmpty) return null;
    return FinancialYear.fromMap(rows.first);
  }

  Future<void> saveFinancialYear(
      FinancialYear fy, String deviceId) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert(
        'financial_years',
        fy.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'financial_years',
        'record_id': fy.id,
        'action': 'EDIT',
        'old_values': null,
        'new_values': jsonEncode(fy.toMap()),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });
    });
  }

  /// Locks a financial year. Only ADMIN or CA should call this.
  Future<void> lockFinancialYear(
      String fyId, String lockedByUserId, String deviceId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'financial_years',
        {
          'is_locked': 1,
          'locked_by': lockedByUserId,
          'locked_at': now,
        },
        where: 'id = ?',
        whereArgs: [fyId],
      );
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'financial_years',
        'record_id': fyId,
        'action': 'EDIT',
        'old_values': jsonEncode({'is_locked': 0}),
        'new_values': jsonEncode({
          'is_locked': 1,
          'locked_by': lockedByUserId,
          'locked_at': now,
        }),
        'timestamp': now,
        'device_id': deviceId,
      });
    });
  }

  /// Unlocks a financial year. Only ADMIN can unlock.
  Future<void> unlockFinancialYear(String fyId, String deviceId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'financial_years',
        {'is_locked': 0, 'locked_by': null, 'locked_at': null},
        where: 'id = ?',
        whereArgs: [fyId],
      );
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'financial_years',
        'record_id': fyId,
        'action': 'EDIT',
        'old_values': jsonEncode({'is_locked': 1}),
        'new_values': jsonEncode({'is_locked': 0}),
        'timestamp': now,
        'device_id': deviceId,
      });
    });
  }
}
