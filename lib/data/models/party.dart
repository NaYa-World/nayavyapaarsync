class Party {
  final String id;
  final String name;
  final String type; // 'SUPPLIER' or 'CUSTOMER'
  final String phone;
  final String address;
  final String? gstin;
  final double openingBalance;
  final String balanceType; // 'DR' or 'CR'
  final DateTime createdAt;
  final bool isDeleted;

  Party({
    required this.id,
    required this.name,
    required this.type,
    required this.phone,
    required this.address,
    this.gstin,
    this.openingBalance = 0.0,
    this.balanceType = 'CR',
    required this.createdAt,
    this.isDeleted = false,
  });

  Party copyWith({
    String? id,
    String? name,
    String? type,
    String? phone,
    String? address,
    String? gstin,
    double? openingBalance,
    String? balanceType,
    DateTime? createdAt,
    bool? isDeleted,
  }) {
    return Party(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      gstin: gstin ?? this.gstin,
      openingBalance: openingBalance ?? this.openingBalance,
      balanceType: balanceType ?? this.balanceType,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'phone': phone,
      'address': address,
      'gstin': gstin,
      'opening_balance': openingBalance,
      'balance_type': balanceType,
      'created_at': createdAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Party.fromMap(Map<String, dynamic> map) {
    return Party(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      phone: map['phone'] as String,
      address: map['address'] as String,
      gstin: map['gstin'] as String?,
      openingBalance: (map['opening_balance'] as num).toDouble(),
      balanceType: map['balance_type'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isDeleted: (map['is_deleted'] as int) == 1,
    );
  }
}
