class BankInstrument {
  final String id;
  final String voucherId;
  final String instrumentType; // 'CHEQUE', 'DD', 'NEFT', 'RTGS', 'UPI'
  final String? instrumentNo;
  final String? bankName;
  final double amount;
  final String status; // 'ISSUED', 'RECEIVED', 'PENDING', 'CLEARED', 'BOUNCED', 'CANCELLED'
  final DateTime? clearedDate;

  BankInstrument({
    required this.id,
    required this.voucherId,
    required this.instrumentType,
    this.instrumentNo,
    this.bankName,
    required this.amount,
    this.status = 'PENDING',
    this.clearedDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voucher_id': voucherId,
      'instrument_type': instrumentType,
      'instrument_no': instrumentNo,
      'bank_name': bankName,
      'amount': amount,
      'status': status,
      'cleared_date': clearedDate?.toIso8601String().substring(0, 10),
    };
  }

  factory BankInstrument.fromMap(Map<String, dynamic> map) {
    return BankInstrument(
      id: map['id'] as String,
      voucherId: map['voucher_id'] as String,
      instrumentType: map['instrument_type'] as String,
      instrumentNo: map['instrument_no'] as String?,
      bankName: map['bank_name'] as String?,
      amount: (map['amount'] as num).toDouble(),
      status: map['status'] as String,
      clearedDate: map['cleared_date'] != null ? DateTime.parse(map['cleared_date'] as String) : null,
    );
  }
}
