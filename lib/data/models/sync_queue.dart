import 'dart:convert';

class SyncQueueItem {
  final String id;
  final String operation; // 'CREATE', 'EDIT', 'DELETE'
  final String tableName;
  final String recordId;
  final String? fieldName; // NULL for CREATE/DELETE, field name for EDIT
  final String? oldValue;
  final String? newValue;
  final Map<String, dynamic>? payload; // JSON snapshot of the record (for CREATE/DELETE)
  final DateTime createdAt;
  final String status; // 'PENDING', 'DONE', 'FAILED', 'SUPERSEDED'
  final String deviceRole; // 'owner' | 'accountant'
  final bool isResolution; // True if this item propagates a conflict resolution

  SyncQueueItem({
    required this.id,
    required this.operation,
    required this.tableName,
    required this.recordId,
    this.fieldName,
    this.oldValue,
    this.newValue,
    this.payload,
    required this.createdAt,
    this.status = 'PENDING',
    this.deviceRole = 'owner',
    this.isResolution = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'operation': operation,
      'table_name': tableName,
      'record_id': recordId,
      'field_name': fieldName,
      'old_value': oldValue,
      'new_value': newValue,
      'payload': payload != null ? jsonEncode(payload) : null,
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'device_role': deviceRole,
      'is_resolution': isResolution ? 1 : 0,
    };
  }

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? payLoadMap;
    if (map['payload'] != null && (map['payload'] as String).isNotEmpty) {
      try {
        payLoadMap = jsonDecode(map['payload'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }

    return SyncQueueItem(
      id: map['id'] as String,
      operation: map['operation'] as String,
      tableName: map['table_name'] as String,
      recordId: map['record_id'] as String,
      fieldName: map['field_name'] as String?,
      oldValue: map['old_value'] as String?,
      newValue: map['new_value'] as String?,
      payload: payLoadMap,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: map['status'] as String,
      deviceRole: map['device_role'] as String? ?? 'owner',
      isResolution: (map['is_resolution'] as int? ?? 0) == 1,
    );
  }
}
