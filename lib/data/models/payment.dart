class Payment {
  final String id;
  final String partyId;
  final String direction; // 'RECEIVED' or 'PAID'
  final double amount;
  final String mode; // 'CASH', 'UPI', 'BANK', 'CHEQUE'
  final DateTime date;
  final String? referenceNo;
  final String? linkedInvoiceId; // purchase_id or sale_id
  final String? notes;
  final DateTime createdAt;
  final bool isDeleted;

  Payment({
    required this.id,
    required this.partyId,
    required this.direction,
    required this.amount,
    required this.mode,
    required this.date,
    this.referenceNo,
    this.linkedInvoiceId,
    this.notes,
    required this.createdAt,
    this.isDeleted = false,
  });

  Payment copyWith({
    String? id,
    String? partyId,
    String? direction,
    double? amount,
    String? mode,
    DateTime? date,
    String? referenceNo,
    String? linkedInvoiceId,
    String? notes,
    DateTime? createdAt,
    bool? isDeleted,
  }) {
    return Payment(
      id: id ?? this.id,
      partyId: partyId ?? this.partyId,
      direction: direction ?? this.direction,
      amount: amount ?? this.amount,
      mode: mode ?? this.mode,
      date: date ?? this.date,
      referenceNo: referenceNo ?? this.referenceNo,
      linkedInvoiceId: linkedInvoiceId ?? this.linkedInvoiceId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'party_id': partyId,
      'direction': direction,
      'amount': amount,
      'mode': mode,
      'date': date.toIso8601String(),
      'reference_no': referenceNo,
      'linked_invoice_id': linkedInvoiceId,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'] as String,
      partyId: map['party_id'] as String,
      direction: map['direction'] as String,
      amount: (map['amount'] as num).toDouble(),
      mode: map['mode'] as String,
      date: DateTime.parse(map['date'] as String),
      referenceNo: map['reference_no'] as String?,
      linkedInvoiceId: map['linked_invoice_id'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      isDeleted: (map['is_deleted'] as int) == 1,
    );
  }
}
