import 'dart:convert';

class SyncQueueItem {
  final String id;
  final String operation; // 'CREATE', 'EDIT', 'DELETE'
  final String tableName;
  final String recordId;
  final Map<String, dynamic>? payload; // JSON snapshot of the record
  final DateTime createdAt;
  final String status; // 'PENDING', 'DONE', 'FAILED'

  SyncQueueItem({
    required this.id,
    required this.operation,
    required this.tableName,
    required this.recordId,
    this.payload,
    required this.createdAt,
    this.status = 'PENDING',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'operation': operation,
      'table_name': tableName,
      'record_id': recordId,
      'payload': payload != null ? jsonEncode(payload) : null,
      'created_at': createdAt.toIso8601String(),
      'status': status,
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
      payload: payLoadMap,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: map['status'] as String,
    );
  }
}
