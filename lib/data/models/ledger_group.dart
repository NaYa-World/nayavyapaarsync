class LedgerGroup {
  final String id;
  final String name;
  final String? parentId;
  final String nature; // 'ASSETS', 'LIABILITIES', 'INCOME', 'EXPENSES'

  LedgerGroup({
    required this.id,
    required this.name,
    this.parentId,
    required this.nature,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'nature': nature,
    };
  }

  factory LedgerGroup.fromMap(Map<String, dynamic> map) {
    return LedgerGroup(
      id: map['id'] as String,
      name: map['name'] as String,
      parentId: map['parent_id'] as String?,
      nature: map['nature'] as String,
    );
  }
}
