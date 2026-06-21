class Batch {
  final String id;
  final String stockItemId;
  final String batchNo;
  final DateTime? expiryDate;
  final DateTime? mfgDate;

  Batch({
    required this.id,
    required this.stockItemId,
    required this.batchNo,
    this.expiryDate,
    this.mfgDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'stock_item_id': stockItemId,
      'batch_no': batchNo,
      'expiry_date': expiryDate?.toIso8601String().substring(0, 10),
      'mfg_date': mfgDate?.toIso8601String().substring(0, 10),
    };
  }

  factory Batch.fromMap(Map<String, dynamic> map) {
    return Batch(
      id: map['id'] as String,
      stockItemId: map['stock_item_id'] as String,
      batchNo: map['batch_no'] as String,
      expiryDate: map['expiry_date'] != null ? DateTime.parse(map['expiry_date'] as String) : null,
      mfgDate: map['mfg_date'] != null ? DateTime.parse(map['mfg_date'] as String) : null,
    );
  }
}
