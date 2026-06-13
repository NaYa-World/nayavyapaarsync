class Item {
  final String id;
  final String name;
  final String category; // 'SEED' or 'FERTILISER'
  final String hsnCode;
  final double gstRate; // 0, 5, 12, 18
  final String primaryUnit; // 'BAG' or 'BOX'
  final double? bagWeightKg;
  final double? boxWeightKg;
  final double lowStockThreshold;
  final DateTime createdAt;
  final bool isDeleted;

  Item({
    required this.id,
    required this.name,
    required this.category,
    required this.hsnCode,
    required this.gstRate,
    required this.primaryUnit,
    this.bagWeightKg,
    this.boxWeightKg,
    this.lowStockThreshold = 10.0,
    required this.createdAt,
    this.isDeleted = false,
  });

  Item copyWith({
    String? id,
    String? name,
    String? category,
    String? hsnCode,
    double? gstRate,
    String? primaryUnit,
    double? bagWeightKg,
    double? boxWeightKg,
    double? lowStockThreshold,
    DateTime? createdAt,
    bool? isDeleted,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      hsnCode: hsnCode ?? this.hsnCode,
      gstRate: gstRate ?? this.gstRate,
      primaryUnit: primaryUnit ?? this.primaryUnit,
      bagWeightKg: bagWeightKg ?? this.bagWeightKg,
      boxWeightKg: boxWeightKg ?? this.boxWeightKg,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'hsn_code': hsnCode,
      'gst_rate': gstRate,
      'primary_unit': primaryUnit,
      'bag_weight_kg': bagWeightKg,
      'box_weight_kg': boxWeightKg,
      'low_stock_threshold': lowStockThreshold,
      'created_at': createdAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      hsnCode: map['hsn_code'] as String,
      gstRate: (map['gst_rate'] as num).toDouble(),
      primaryUnit: map['primary_unit'] as String,
      bagWeightKg: map['bag_weight_kg'] != null ? (map['bag_weight_kg'] as num).toDouble() : null,
      boxWeightKg: map['box_weight_kg'] != null ? (map['box_weight_kg'] as num).toDouble() : null,
      lowStockThreshold: (map['low_stock_threshold'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      isDeleted: (map['is_deleted'] as int) == 1,
    );
  }
}
