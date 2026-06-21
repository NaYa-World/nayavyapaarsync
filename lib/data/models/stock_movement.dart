class StockMovement {
  final String id;
  final String stockItemId;
  final String godownId;
  final String refVoucherId;
  final double qty;
  final double rate;
  final String movementType; // 'IN' or 'OUT'
  final String? batchId;
  final DateTime createdAt;

  StockMovement({
    required this.id,
    required this.stockItemId,
    required this.godownId,
    required this.refVoucherId,
    required this.qty,
    required this.rate,
    required this.movementType,
    this.batchId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'stock_item_id': stockItemId,
      'godown_id': godownId,
      'ref_voucher_id': refVoucherId,
      'qty': qty,
      'rate': rate,
      'movement_type': movementType,
      'batch_id': batchId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    return StockMovement(
      id: map['id'] as String,
      stockItemId: map['stock_item_id'] as String,
      godownId: map['godown_id'] as String,
      refVoucherId: map['ref_voucher_id'] as String,
      qty: (map['qty'] as num).toDouble(),
      rate: (map['rate'] as num).toDouble(),
      movementType: map['movement_type'] as String,
      batchId: map['batch_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
