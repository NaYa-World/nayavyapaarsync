class VoucherLine {
  final String id;
  final String voucherId;
  final String ledgerId;
  final double drAmount;
  final double crAmount;
  final String? narration;

  VoucherLine({
    required this.id,
    required this.voucherId,
    required this.ledgerId,
    this.drAmount = 0.0,
    this.crAmount = 0.0,
    this.narration,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voucher_id': voucherId,
      'ledger_id': ledgerId,
      'dr_amount': drAmount,
      'cr_amount': crAmount,
      'narration': narration,
    };
  }

  factory VoucherLine.fromMap(Map<String, dynamic> map) {
    return VoucherLine(
      id: map['id'] as String,
      voucherId: map['voucher_id'] as String,
      ledgerId: map['ledger_id'] as String,
      drAmount: (map['dr_amount'] as num).toDouble(),
      crAmount: (map['cr_amount'] as num).toDouble(),
      narration: map['narration'] as String?,
    );
  }
}
