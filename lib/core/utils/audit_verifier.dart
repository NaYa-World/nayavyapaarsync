import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

class AuditVerificationResult {
  final bool isValid;
  final String? errorReason;
  final String? corruptedRecordId;
  final List<String> details;

  AuditVerificationResult({
    required this.isValid,
    this.errorReason,
    this.corruptedRecordId,
    required this.details,
  });
}

class AuditVerifier {
  /// Genesis block seed for the chain
  static const String genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';

  /// Verifies the entire integrity of the cryptographic audit chain.
  /// Walks sequentially through all records ordered by timestamp ASC, id ASC.
  static Future<AuditVerificationResult> verifyChain(DatabaseExecutor db) async {
    final List<Map<String, dynamic>> logs = await db.query(
      'audit_logs',
      orderBy: 'timestamp ASC, id ASC',
    );

    final List<String> details = [];
    if (logs.isEmpty) {
      details.add('Audit log is empty. Chain is valid by default.');
      return AuditVerificationResult(isValid: true, details: details);
    }

    String expectedPrevHash = genesisHash;

    for (int i = 0; i < logs.length; i++) {
      final log = logs[i];
      final String id = log['id'] as String;
      final String tableName = log['table_name'] as String;
      final String recordId = log['record_id'] as String;
      final String action = log['action'] as String;
      final String oldValues = log['old_values'] as String? ?? '';
      final String newValues = log['new_values'] as String? ?? '';
      final String timestamp = log['timestamp'] as String;
      final String deviceId = log['device_id'] as String;
      final String? storedHash = log['hash'] as String?;
      final String? storedPrevHash = log['prev_hash'] as String?;

      if (storedHash == null || storedPrevHash == null) {
        details.add('Record $id: Missing cryptographic hash or prev_hash.');
        return AuditVerificationResult(
          isValid: false,
          errorReason: 'Missing cryptographic fields',
          corruptedRecordId: id,
          details: details,
        );
      }

      // 1. Verify prev_hash link matches
      if (storedPrevHash != expectedPrevHash) {
        details.add('Record $id: Link corruption. Expected prev_hash: $expectedPrevHash, stored: $storedPrevHash');
        return AuditVerificationResult(
          isValid: false,
          errorReason: 'Hash chain link broken',
          corruptedRecordId: id,
          details: details,
        );
      }

      // 2. Recalculate hash of current block
      final String payload = '$tableName|$recordId|$action|$oldValues|$newValues|$timestamp|$deviceId|$storedPrevHash';
      final String calculatedHash = sha256.convert(utf8.encode(payload)).toString();

      if (storedHash != calculatedHash) {
        details.add('Record $id: Content corruption. Calculated hash: $calculatedHash, stored: $storedHash');
        return AuditVerificationResult(
          isValid: false,
          errorReason: 'Content modified / tampered',
          corruptedRecordId: id,
          details: details,
        );
      }

      details.add('Record $id (Index $i): Verified successfully.');
      expectedPrevHash = storedHash;
    }

    details.add('Successfully verified all ${logs.length} records in the chain.');
    return AuditVerificationResult(isValid: true, details: details);
  }
}
