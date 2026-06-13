class BackupMeta {
  final String id;
  final DateTime timestamp;
  final String gdriveFileId;
  final int fileSize;
  final String status; // 'SUCCESS' or 'FAILED'
  final String deviceId;

  BackupMeta({
    required this.id,
    required this.timestamp,
    required this.gdriveFileId,
    required this.fileSize,
    required this.status,
    required this.deviceId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'gdrive_file_id': gdriveFileId,
      'file_size': fileSize,
      'status': status,
      'device_id': deviceId,
    };
  }

  factory BackupMeta.fromMap(Map<String, dynamic> map) {
    return BackupMeta(
      id: map['id'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      gdriveFileId: map['gdrive_file_id'] as String,
      fileSize: map['file_size'] as int,
      status: map['status'] as String,
      deviceId: map['device_id'] as String,
    );
  }
}
