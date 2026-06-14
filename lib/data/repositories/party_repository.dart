import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/party.dart';
import '../database/db_helper.dart';

class LedgerRow {
  final DateTime date;
  final String narration;
  final double? debit;
  final double? credit;
  final double runningBalance;
  final String runningBalanceType; // 'DR' or 'CR'

  LedgerRow({
    required this.date,
    required this.narration,
    this.debit,
    this.credit,
    required this.runningBalance,
    required this.runningBalanceType,
  });
}

class PartyRepository {
  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Fetches all parties that are not soft-deleted
  Future<List<Party>> getParties() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'parties',
      where: 'is_deleted = 0',
      orderBy: 'name ASC',
    );
    return List.generate(maps.length, (i) => Party.fromMap(maps[i]));
  }

  /// Fetches a specific party by ID
  Future<Party?> getParty(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'parties',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Party.fromMap(maps.first);
  }

  /// Inserts a new party, writes to AuditLog and SyncQueue in a txn
  Future<void> insertParty(Party party, String deviceId) async {
    final db = await _dbHelper.database;
    final map = party.toMap();

    await db.transaction((txn) async {
      await txn.insert('parties', map);

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'parties',
        'record_id': party.id,
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
        'table_name': 'parties',
        'record_id': party.id,
        'payload': jsonEncode(map),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Updates a party, writes to AuditLog and SyncQueue in a txn
  Future<void> updateParty(Party party, String deviceId) async {
    final db = await _dbHelper.database;
    final currentParty = await getParty(party.id);
    if (currentParty == null) return;
    final map = party.toMap();

    await db.transaction((txn) async {
      await txn.update(
        'parties',
        map,
        where: 'id = ?',
        whereArgs: [party.id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'parties',
        'record_id': party.id,
        'action': 'EDIT',
        'old_values': jsonEncode(currentParty.toMap()),
        'new_values': jsonEncode(map),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'EDIT',
        'table_name': 'parties',
        'record_id': party.id,
        'payload': jsonEncode(map),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Soft deletes a party (retained in recycle bin for 30 days)
  Future<void> deleteParty(String id, String deviceId) async {
    final db = await _dbHelper.database;
    final currentParty = await getParty(id);
    if (currentParty == null) return;

    final updatedMap = currentParty.copyWith(isDeleted: true).toMap();

    await db.transaction((txn) async {
      await txn.update(
        'parties',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      // Audit Log
      await txn.insert('audit_logs', {
        'id': _uuid.v4(),
        'table_name': 'parties',
        'record_id': id,
        'action': 'DELETE',
        'old_values': jsonEncode(currentParty.toMap()),
        'new_values': jsonEncode(updatedMap),
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': deviceId,
      });

      // Sync Queue
      await txn.insert('sync_queue', {
        'id': _uuid.v4(),
        'operation': 'DELETE',
        'table_name': 'parties',
        'record_id': id,
        'payload': jsonEncode(updatedMap),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'PENDING',
      });
    });
  }

  /// Calculates outstanding balance for a party.
  /// Returns a map with 'balance' (double) and 'type' (DR/CR)
  Future<Map<String, dynamic>> getOutstandingBalance(String partyId) async {
    final db = await _dbHelper.database;
    final party = await getParty(partyId);
    if (party == null) return {'balance': 0.0, 'type': 'CR'};

    // 1. Purchases total (CR for supplier)
    final List<Map<String, dynamic>> purchaseRes = await db.rawQuery('''
      SELECT COALESCE(SUM(grand_total), 0.0) as total FROM purchases WHERE party_id = ? AND is_deleted = 0
    ''', [partyId]);

    // 2. Sales total (DR for customer)
    final List<Map<String, dynamic>> saleRes = await db.rawQuery('''
      SELECT COALESCE(SUM(grand_total), 0.0) as total FROM sales WHERE party_id = ? AND is_deleted = 0
    ''', [partyId]);

    // 3. Payments made (direction 'PAID' -> DR for supplier)
    final List<Map<String, dynamic>> paidRes = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0.0) as total FROM payments WHERE party_id = ? AND direction = 'PAID' AND is_deleted = 0
    ''', [partyId]);

    // 4. Payments received (direction 'RECEIVED' -> CR for customer)
    final List<Map<String, dynamic>> receivedRes = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0.0) as total FROM payments WHERE party_id = ? AND direction = 'RECEIVED' AND is_deleted = 0
    ''', [partyId]);

    final double purchasesVal = (purchaseRes.first['total'] as num).toDouble();
    final double salesVal = (saleRes.first['total'] as num).toDouble();
    final double paidVal = (paidRes.first['total'] as num).toDouble();
    final double receivedVal = (receivedRes.first['total'] as num).toDouble();

    double runningValue = 0.0;

    if (party.type == 'CUSTOMER') {
      // Net Receivables (DR positive)
      // Opening DR is positive, Opening CR is negative
      final double openingVal = party.openingBalance * (party.balanceType == 'DR' ? 1.0 : -1.0);
      runningValue = openingVal + salesVal - receivedVal;

      if (runningValue >= 0) {
        return {'balance': runningValue, 'type': 'DR'};
      } else {
        return {'balance': runningValue.abs(), 'type': 'CR'};
      }
    } else {
      // Net Payables (CR positive)
      // Opening CR is positive, Opening DR is negative
      final double openingVal = party.openingBalance * (party.balanceType == 'CR' ? 1.0 : -1.0);
      runningValue = openingVal + purchasesVal - paidVal;

      if (runningValue >= 0) {
        return {'balance': runningValue, 'type': 'CR'};
      } else {
        return {'balance': runningValue.abs(), 'type': 'DR'};
      }
    }
  }

  /// Builds a complete running ledger statement for a party.
  /// Returns a sorted list of LedgerRows
  Future<List<LedgerRow>> getLedgerStatement(String partyId) async {
    final db = await _dbHelper.database;
    final party = await getParty(partyId);
    if (party == null) return [];

    // Query purchases
    final List<Map<String, dynamic>> purchaseRows = await db.rawQuery('''
      SELECT invoice_no, date, grand_total as amount FROM purchases WHERE party_id = ? AND is_deleted = 0
    ''', [partyId]);

    // Query sales
    final List<Map<String, dynamic>> saleRows = await db.rawQuery('''
      SELECT invoice_no, date, grand_total as amount FROM sales WHERE party_id = ? AND is_deleted = 0
    ''', [partyId]);

    // Query payments
    final List<Map<String, dynamic>> paymentRows = await db.rawQuery('''
      SELECT direction, mode, reference_no, date, amount FROM payments WHERE party_id = ? AND is_deleted = 0
    ''', [partyId]);

    final List<Map<String, dynamic>> ledgerEvents = [];

    // Add Purchases (Credit for Supplier)
    for (final row in purchaseRows) {
      ledgerEvents.add({
        'date': row['date'],
        'narration': 'Invoice No: ${row['invoice_no']}',
        'debit': null,
        'credit': (row['amount'] as num).toDouble(),
      });
    }

    // Add Sales (Debit for Customer)
    for (final row in saleRows) {
      ledgerEvents.add({
        'date': row['date'],
        'narration': 'Invoice No: ${row['invoice_no']}',
        'debit': (row['amount'] as num).toDouble(),
        'credit': null,
      });
    }

    // Add Payments
    for (final row in paymentRows) {
      final String dir = row['direction'] as String;
      final String mode = row['mode'] as String;
      final String? ref = row['reference_no'] as String?;
      final double amt = (row['amount'] as num).toDouble();
      
      final String refStr = (ref != null && ref.isNotEmpty) ? ' (Ref: $ref)' : '';
      
      if (dir == 'RECEIVED') {
        // Customer paid us -> Credit for customer
        ledgerEvents.add({
          'date': row['date'],
          'narration': 'Payment Received [$mode]$refStr',
          'debit': null,
          'credit': amt,
        });
      } else {
        // We paid supplier -> Debit for supplier
        ledgerEvents.add({
          'date': row['date'],
          'narration': 'Payment Paid [$mode]$refStr',
          'debit': amt,
          'credit': null,
        });
      }
    }

    // Sort chronologically
    ledgerEvents.sort((a, b) {
      final DateTime dateA = DateTime.parse(a['date'] as String);
      final DateTime dateB = DateTime.parse(b['date'] as String);
      return dateA.compareTo(dateB);
    });

    final List<LedgerRow> statement = [];

    // Compute running balance starting with opening balance
    double currentBal = 0.0;
    
    // Add Opening Balance Row
    if (party.type == 'CUSTOMER') {
      currentBal = party.openingBalance * (party.balanceType == 'DR' ? 1.0 : -1.0);
    } else {
      currentBal = party.openingBalance * (party.balanceType == 'CR' ? 1.0 : -1.0);
    }

    statement.add(LedgerRow(
      date: party.createdAt,
      narration: 'Opening Balance',
      debit: party.balanceType == 'DR' ? party.openingBalance : null,
      credit: party.balanceType == 'CR' ? party.openingBalance : null,
      runningBalance: party.openingBalance,
      runningBalanceType: party.balanceType,
    ));

    for (final event in ledgerEvents) {
      final DateTime date = DateTime.parse(event['date'] as String);
      final String narration = event['narration'] as String;
      final double? debit = event['debit'];
      final double? credit = event['credit'];

      if (party.type == 'CUSTOMER') {
        if (debit != null) currentBal += debit;
        if (credit != null) currentBal -= credit;

        statement.add(LedgerRow(
          date: date,
          narration: narration,
          debit: debit,
          credit: credit,
          runningBalance: currentBal.abs(),
          runningBalanceType: currentBal >= 0 ? 'DR' : 'CR',
        ));
      } else {
        if (credit != null) currentBal += credit;
        if (debit != null) currentBal -= debit;

        statement.add(LedgerRow(
          date: date,
          narration: narration,
          debit: debit,
          credit: credit,
          runningBalance: currentBal.abs(),
          runningBalanceType: currentBal >= 0 ? 'CR' : 'DR',
        ));
      }
    }

    return statement.reversed.toList(); // Return reverse sorted so newest is first in UI
  }
}
