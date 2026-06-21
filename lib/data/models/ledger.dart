class Ledger {
  final String id;
  final String name;
  final String groupId;
  final double openingBalance;
  final String balanceType; // 'DR' or 'CR'
  final String companyId;
  final bool isActive;
  final DateTime createdAt;

  Ledger({
    required this.id,
    required this.name,
    required this.groupId,
    this.openingBalance = 0.0,
    required this.balanceType,
    required this.companyId,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'group_id': groupId,
      'opening_balance': openingBalance,
      'balance_type': balanceType,
      'company_id': companyId,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Ledger.fromMap(Map<String, dynamic> map) {
    return Ledger(
      id: map['id'] as String,
      name: map['name'] as String,
      groupId: map['group_id'] as String,
      openingBalance: (map['opening_balance'] as num).toDouble(),
      balanceType: map['balance_type'] as String,
      companyId: map['company_id'] as String,
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
