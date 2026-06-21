class Company {
  final String id;
  final String name;
  final String? gstin;
  final String? address;
  final String? phone;
  final String state;
  final String stateCode;
  final bool isActive;
  final DateTime createdAt;

  const Company({
    required this.id,
    required this.name,
    this.gstin,
    this.address,
    this.phone,
    this.state = 'Telangana',
    this.stateCode = '36',
    this.isActive = true,
    required this.createdAt,
  });

  Company copyWith({
    String? id,
    String? name,
    String? gstin,
    String? address,
    String? phone,
    String? state,
    String? stateCode,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Company(
      id: id ?? this.id,
      name: name ?? this.name,
      gstin: gstin ?? this.gstin,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      state: state ?? this.state,
      stateCode: stateCode ?? this.stateCode,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Company.fromMap(Map<String, dynamic> map) {
    return Company(
      id: map['id'] as String,
      name: map['name'] as String,
      gstin: map['gstin'] as String?,
      address: map['address'] as String?,
      phone: map['phone'] as String?,
      state: (map['state'] as String?) ?? 'Telangana',
      stateCode: (map['state_code'] as String?) ?? '36',
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'gstin': gstin,
      'address': address,
      'phone': phone,
      'state': state,
      'state_code': stateCode,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
