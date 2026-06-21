class Godown {
  final String id;
  final String companyId;
  final String name;
  final String? address;
  final bool isActive;
  final DateTime createdAt;

  Godown({
    required this.id,
    required this.companyId,
    required this.name,
    this.address,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'name': name,
      'address': address,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Godown.fromMap(Map<String, dynamic> map) {
    return Godown(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
