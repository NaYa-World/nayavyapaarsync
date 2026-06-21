class AppUser {
  final String id;
  final String name;
  final String pinHash; // SHA-256 of PIN
  final String? salt;
  final String role; // ADMIN | CA | ACCOUNTANT | MANAGER
  final String? companyId;
  final bool isActive;
  final DateTime createdAt;

  static const List<String> roles = ['ADMIN', 'CA', 'ACCOUNTANT', 'MANAGER'];

  const AppUser({
    required this.id,
    required this.name,
    required this.pinHash,
    this.salt,
    required this.role,
    this.companyId,
    this.isActive = true,
    required this.createdAt,
  });

  /// Returns display-friendly role label
  String get roleLabel {
    switch (role) {
      case 'ADMIN':
        return 'Admin';
      case 'CA':
        return 'CA (Chartered Accountant)';
      case 'ACCOUNTANT':
        return 'Accountant';
      case 'MANAGER':
        return 'Manager';
      default:
        return role;
    }
  }

  /// Whether this role can lock/unlock financial years
  bool get canLockFY => role == 'ADMIN' || role == 'CA';

  /// Whether this role can create/edit vouchers
  bool get canEditVouchers => role != 'MANAGER';

  /// Whether this role can manage other users
  bool get canManageUsers => role == 'ADMIN';

  AppUser copyWith({
    String? id,
    String? name,
    String? pinHash,
    String? salt,
    String? role,
    String? companyId,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      pinHash: pinHash ?? this.pinHash,
      salt: salt ?? this.salt,
      role: role ?? this.role,
      companyId: companyId ?? this.companyId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      name: map['name'] as String,
      pinHash: map['pin_hash'] as String,
      salt: map['salt'] as String?,
      role: map['role'] as String,
      companyId: map['company_id'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'pin_hash': pinHash,
      'salt': salt,
      'role': role,
      'company_id': companyId,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
