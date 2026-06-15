class FinancialYear {
  final String id;
  final String companyId;
  final String label; // e.g. "FY 2024-25"
  final DateTime startDate;
  final DateTime endDate;
  final bool isLocked;
  final String? lockedBy;
  final DateTime? lockedAt;

  const FinancialYear({
    required this.id,
    required this.companyId,
    required this.label,
    required this.startDate,
    required this.endDate,
    this.isLocked = false,
    this.lockedBy,
    this.lockedAt,
  });

  bool containsDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  FinancialYear copyWith({
    String? id,
    String? companyId,
    String? label,
    DateTime? startDate,
    DateTime? endDate,
    bool? isLocked,
    String? lockedBy,
    DateTime? lockedAt,
  }) {
    return FinancialYear(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      label: label ?? this.label,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isLocked: isLocked ?? this.isLocked,
      lockedBy: lockedBy ?? this.lockedBy,
      lockedAt: lockedAt ?? this.lockedAt,
    );
  }

  factory FinancialYear.fromMap(Map<String, dynamic> map) {
    return FinancialYear(
      id: map['id'] as String,
      companyId: map['company_id'] as String,
      label: map['label'] as String,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: DateTime.parse(map['end_date'] as String),
      isLocked: (map['is_locked'] as int? ?? 0) == 1,
      lockedBy: map['locked_by'] as String?,
      lockedAt: map['locked_at'] != null
          ? DateTime.parse(map['locked_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'label': label,
      'start_date': startDate.toIso8601String().substring(0, 10),
      'end_date': endDate.toIso8601String().substring(0, 10),
      'is_locked': isLocked ? 1 : 0,
      'locked_by': lockedBy,
      'locked_at': lockedAt?.toIso8601String(),
    };
  }
}
