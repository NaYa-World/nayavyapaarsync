class Voucher {
  final String id;
  final String voucherNo;
  final String type; // 'SALE', 'PURCHASE', 'RECEIPT', 'PAYMENT', 'CONTRA', 'JOURNAL', 'CREDIT_NOTE', 'DEBIT_NOTE'
  final DateTime date;
  final String? narration;
  final String companyId;
  final String fyId;
  final bool isLocked;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  final bool isCancelled;

  Voucher({
    required this.id,
    required this.voucherNo,
    required this.type,
    required this.date,
    this.narration,
    required this.companyId,
    required this.fyId,
    this.isLocked = false,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.isCancelled = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voucher_no': voucherNo,
      'type': type,
      'date': date.toIso8601String(),
      'narration': narration,
      'company_id': companyId,
      'fy_id': fyId,
      'is_locked': isLocked ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
      'is_cancelled': isCancelled ? 1 : 0,
    };
  }

  factory Voucher.fromMap(Map<String, dynamic> map) {
    return Voucher(
      id: map['id'] as String,
      voucherNo: map['voucher_no'] as String,
      type: map['type'] as String,
      date: DateTime.parse(map['date'] as String),
      narration: map['narration'] as String?,
      companyId: map['company_id'] as String,
      fyId: map['fy_id'] as String,
      isLocked: (map['is_locked'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isDeleted: (map['is_deleted'] as int) == 1,
      isCancelled: (map['is_cancelled'] as int? ?? 0) == 1,
    );
  }
}
