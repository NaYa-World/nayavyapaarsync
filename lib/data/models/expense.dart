class Expense {
  final String id;
  final String category; // 'RENT', 'ELECTRICITY', 'SALARY', 'HAMALI', 'MAINTENANCE', 'FUEL', 'OTHER'
  final double amount;
  final DateTime date;
  final String description;
  final String paymentMethod; // 'CASH', 'BANK'
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    required this.description,
    required this.paymentMethod,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  Expense copyWith({
    String? id,
    String? category,
    double? amount,
    DateTime? date,
    String? description,
    String? paymentMethod,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Expense(
      id: id ?? this.id,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      description: description ?? this.description,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'amount': amount,
      'date': date.toIso8601String(),
      'description': description,
      'payment_method': paymentMethod,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      category: map['category'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      description: map['description'] as String? ?? '',
      paymentMethod: map['payment_method'] as String? ?? 'CASH',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isDeleted: (map['is_deleted'] as int) == 1,
    );
  }
}
