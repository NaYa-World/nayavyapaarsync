class BankReconciliation {
  final String id;
  final String ledgerId;
  final DateTime statementDate;
  final double closingBalanceBank;
  final double closingBalanceBook;
  final double difference;
  final String reconciledBy;
  final DateTime reconciledAt;

  BankReconciliation({
    required this.id,
    required this.ledgerId,
    required this.statementDate,
    required this.closingBalanceBank,
    required this.closingBalanceBook,
    required this.difference,
    required this.reconciledBy,
    required this.reconciledAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ledger_id': ledgerId,
      'statement_date': statementDate.toIso8601String().substring(0, 10),
      'closing_balance_bank': closingBalanceBank,
      'closing_balance_book': closingBalanceBook,
      'difference': difference,
      'reconciled_by': reconciledBy,
      'reconciled_at': reconciledAt.toIso8601String(),
    };
  }

  factory BankReconciliation.fromMap(Map<String, dynamic> map) {
    return BankReconciliation(
      id: map['id'] as String,
      ledgerId: map['ledger_id'] as String,
      statementDate: DateTime.parse(map['statement_date'] as String),
      closingBalanceBank: (map['closing_balance_bank'] as num).toDouble(),
      closingBalanceBook: (map['closing_balance_book'] as num).toDouble(),
      difference: (map['difference'] as num).toDouble(),
      reconciledBy: map['reconciled_by'] as String,
      reconciledAt: DateTime.parse(map['reconciled_at'] as String),
    );
  }
}
