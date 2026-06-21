class BillAllocation {
  final String id;
  final String voucherLineId;
  final String refVoucherId; // The invoice voucher being paid
  final double allocatedAmount;
  final double outstandingAmount;
  final String status; // 'OPEN', 'PART_PAID', 'CLOSED'

  BillAllocation({
    required this.id,
    required this.voucherLineId,
    required this.refVoucherId,
    required this.allocatedAmount,
    required this.outstandingAmount,
    this.status = 'OPEN',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voucher_line_id': voucherLineId,
      'ref_voucher_id': refVoucherId,
      'allocated_amount': allocatedAmount,
      'outstanding_amount': outstandingAmount,
      'status': status,
    };
  }

  factory BillAllocation.fromMap(Map<String, dynamic> map) {
    return BillAllocation(
      id: map['id'] as String,
      voucherLineId: map['voucher_line_id'] as String,
      refVoucherId: map['ref_voucher_id'] as String,
      allocatedAmount: (map['allocated_amount'] as num).toDouble(),
      outstandingAmount: (map['outstanding_amount'] as num).toDouble(),
      status: map['status'] as String,
    );
  }
}
