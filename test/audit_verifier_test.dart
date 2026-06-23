import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:godown_management/data/database/db_helper.dart';
import 'package:godown_management/core/utils/audit_verifier.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Cryptographic Audit Verifier Tests', () {
    late DbHelper dbHelper;
    late Database db;

    setUp(() async {
      dbHelper = DbHelper();
      db = await dbHelper.database;
      await db.delete('audit_logs');
    });

    tearDown(() async {
      // Clear logs to avoid interfering with other tests
      await db.delete('audit_logs');
    });

    test('Empty audit log is valid', () async {
      final result = await AuditVerifier.verifyChain(db);
      expect(result.isValid, isTrue);
      expect(result.details.first, contains('Audit log is empty'));
    });

    test('Valid audit log chain passes verification', () async {
      await dbHelper.insertAuditLog(
        db,
        id: 'log-1',
        tableName: 'items',
        recordId: 'item-1',
        action: 'CREATE',
        oldValues: null,
        newValues: '{"name": "Item 1"}',
        timestamp: '2026-06-23T12:00:00Z',
        deviceId: 'device-1',
      );

      await dbHelper.insertAuditLog(
        db,
        id: 'log-2',
        tableName: 'items',
        recordId: 'item-1',
        action: 'EDIT',
        oldValues: '{"name": "Item 1"}',
        newValues: '{"name": "Item 1 edited"}',
        timestamp: '2026-06-23T12:05:00Z',
        deviceId: 'device-1',
      );

      await dbHelper.insertAuditLog(
        db,
        id: 'log-3',
        tableName: 'items',
        recordId: 'item-1',
        action: 'DELETE',
        oldValues: '{"name": "Item 1 edited"}',
        newValues: null,
        timestamp: '2026-06-23T12:10:00Z',
        deviceId: 'device-1',
      );

      final result = await AuditVerifier.verifyChain(db);
      expect(result.isValid, isTrue);
      expect(result.details.length, 4); // 3 verified entries + final success message
    });

    test('Detects record content modification/tampering', () async {
      await dbHelper.insertAuditLog(
        db,
        id: 'log-1',
        tableName: 'items',
        recordId: 'item-1',
        action: 'CREATE',
        oldValues: null,
        newValues: '{"name": "Item 1"}',
        timestamp: '2026-06-23T12:00:00Z',
        deviceId: 'device-1',
      );

      await dbHelper.insertAuditLog(
        db,
        id: 'log-2',
        tableName: 'items',
        recordId: 'item-1',
        action: 'EDIT',
        oldValues: '{"name": "Item 1"}',
        newValues: '{"name": "Item 1 edited"}',
        timestamp: '2026-06-23T12:05:00Z',
        deviceId: 'device-1',
      );

      var result = await AuditVerifier.verifyChain(db);
      expect(result.isValid, isTrue);

      // Tamper with content
      await db.update(
        'audit_logs',
        {'new_values': '{"name": "Item 1 Tampered"}'},
        where: 'id = ?',
        whereArgs: ['log-1'],
      );

      result = await AuditVerifier.verifyChain(db);
      expect(result.isValid, isFalse);
      expect(result.errorReason, equals('Content modified / tampered'));
      expect(result.corruptedRecordId, equals('log-1'));
    });

    test('Detects middle-row deletion in audit log', () async {
      await dbHelper.insertAuditLog(
        db,
        id: 'log-1',
        tableName: 'items',
        recordId: 'item-1',
        action: 'CREATE',
        oldValues: null,
        newValues: '{"name": "Item 1"}',
        timestamp: '2026-06-23T12:00:00Z',
        deviceId: 'device-1',
      );

      await dbHelper.insertAuditLog(
        db,
        id: 'log-2',
        tableName: 'items',
        recordId: 'item-1',
        action: 'EDIT',
        oldValues: '{"name": "Item 1"}',
        newValues: '{"name": "Item 1 edited"}',
        timestamp: '2026-06-23T12:05:00Z',
        deviceId: 'device-1',
      );

      await dbHelper.insertAuditLog(
        db,
        id: 'log-3',
        tableName: 'items',
        recordId: 'item-1',
        action: 'DELETE',
        oldValues: '{"name": "Item 1 edited"}',
        newValues: null,
        timestamp: '2026-06-23T12:10:00Z',
        deviceId: 'device-1',
      );

      var result = await AuditVerifier.verifyChain(db);
      expect(result.isValid, isTrue);

      // Delete log-2
      await db.delete(
        'audit_logs',
        where: 'id = ?',
        whereArgs: ['log-2'],
      );

      result = await AuditVerifier.verifyChain(db);
      expect(result.isValid, isFalse);
      expect(result.errorReason, equals('Hash chain link broken'));
      expect(result.corruptedRecordId, equals('log-3'));
    });

    test('Detects missing cryptographic values', () async {
      await dbHelper.insertAuditLog(
        db,
        id: 'log-1',
        tableName: 'items',
        recordId: 'item-1',
        action: 'CREATE',
        oldValues: null,
        newValues: '{"name": "Item 1"}',
        timestamp: '2026-06-23T12:00:00Z',
        deviceId: 'device-1',
      );

      await db.update(
        'audit_logs',
        {'hash': null},
        where: 'id = ?',
        whereArgs: ['log-1'],
      );

      final result = await AuditVerifier.verifyChain(db);
      expect(result.isValid, isFalse);
      expect(result.errorReason, equals('Missing cryptographic fields'));
      expect(result.corruptedRecordId, equals('log-1'));
    });
  });
}
