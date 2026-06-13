import 'dart:convert';

class AuditLog {
  final String id;
  final String tableName;
  final String recordId;
  final String action; // 'CREATE', 'EDIT', 'DELETE'
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final DateTime timestamp;
  final String deviceId;

  AuditLog({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.action,
    this.oldValues,
    this.newValues,
    required this.timestamp,
    required this.deviceId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table_name': tableName,
      'record_id': recordId,
      'action': action,
      'old_values': oldValues != null ? jsonEncode(oldValues) : null,
      'new_values': newValues != null ? jsonEncode(newValues) : null,
      'timestamp': timestamp.toIso8601String(),
      'device_id': deviceId,
    };
  }

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? oldVals;
    if (map['old_values'] != null && (map['old_values'] as String).isNotEmpty) {
      try {
        oldVals = jsonDecode(map['old_values'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }

    Map<String, dynamic>? newVals;
    if (map['new_values'] != null && (map['new_values'] as String).isNotEmpty) {
      try {
        newVals = jsonDecode(map['new_values'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }

    return AuditLog(
      id: map['id'] as String,
      tableName: map['table_name'] as String,
      recordId: map['record_id'] as String,
      action: map['action'] as String,
      oldValues: oldVals,
      newValues: newVals,
      timestamp: DateTime.parse(map['timestamp'] as String),
      deviceId: map['device_id'] as String,
    );
  }
}
