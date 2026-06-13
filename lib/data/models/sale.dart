import 'dart:convert';

class Sale {
  final String id;
  final String invoiceNo;
  final String partyId;
  final DateTime date;
  final double subtotal;
  final double gstTotal;
  final double grandTotal;
  final String paymentStatus; // 'PAID', 'PARTIAL', 'PENDING'
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  final List<dynamic> editHistory; // JSON array mapped to List
  final String category; // 'SEED' or 'FERTILISER'

  Sale({
    required this.id,
    required this.invoiceNo,
    required this.partyId,
    required this.date,
    required this.subtotal,
    required this.gstTotal,
    required this.grandTotal,
    required this.paymentStatus,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.editHistory = const [],
    required this.category,
  });

  Sale copyWith({
    String? id,
    String? invoiceNo,
    String? partyId,
    DateTime? date,
    double? subtotal,
    double? gstTotal,
    double? grandTotal,
    String? paymentStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    List<dynamic>? editHistory,
    String? category,
  }) {
    return Sale(
      id: id ?? this.id,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      partyId: partyId ?? this.partyId,
      date: date ?? this.date,
      subtotal: subtotal ?? this.subtotal,
      gstTotal: gstTotal ?? this.gstTotal,
      grandTotal: grandTotal ?? this.grandTotal,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      editHistory: editHistory ?? this.editHistory,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_no': invoiceNo,
      'party_id': partyId,
      'date': date.toIso8601String(),
      'subtotal': subtotal,
      'gst_total': gstTotal,
      'grand_total': grandTotal,
      'payment_status': paymentStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
      'edit_history': jsonEncode(editHistory),
      'category': category,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    List<dynamic> parsedHistory = [];
    if (map['edit_history'] != null && (map['edit_history'] as String).isNotEmpty) {
      try {
        parsedHistory = jsonDecode(map['edit_history'] as String) as List<dynamic>;
      } catch (_) {
        parsedHistory = [];
      }
    }

    return Sale(
      id: map['id'] as String,
      invoiceNo: map['invoice_no'] as String,
      partyId: map['party_id'] as String,
      date: DateTime.parse(map['date'] as String),
      subtotal: (map['subtotal'] as num).toDouble(),
      gstTotal: (map['gst_total'] as num).toDouble(),
      grandTotal: (map['grand_total'] as num).toDouble(),
      paymentStatus: map['payment_status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isDeleted: (map['is_deleted'] as int) == 1,
      editHistory: parsedHistory,
      category: map['category'] as String? ?? 'SEED',
    );
  }
}

class SaleItem {
  final String id;
  final String saleId;
  final String itemId;
  final double qty;
  final double rate;
  final double gstRate;
  final double gstAmt;
  final double total;
  final String? manufacturer;
  final String? packing;
  final String? batchNo;
  final String? hsnCode;
  final String? mfgDate;
  final String? expDate;
  final double? unitPerCase;
  final double? noOfCases;
  final double? totalUnits;
  final double? unitPrice;

  SaleItem({
    required this.id,
    required this.saleId,
    required this.itemId,
    required this.qty,
    required this.rate,
    required this.gstRate,
    required this.gstAmt,
    required this.total,
    this.manufacturer,
    this.packing,
    this.batchNo,
    this.hsnCode,
    this.mfgDate,
    this.expDate,
    this.unitPerCase,
    this.noOfCases,
    this.totalUnits,
    this.unitPrice,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sale_id': saleId,
      'item_id': itemId,
      'qty': qty,
      'rate': rate,
      'gst_rate': gstRate,
      'gst_amt': gstAmt,
      'total': total,
      'manufacturer': manufacturer,
      'packing': packing,
      'batch_no': batchNo,
      'hsn_code': hsnCode,
      'mfg_date': mfgDate,
      'exp_date': expDate,
      'unit_per_case': unitPerCase,
      'no_of_cases': noOfCases,
      'total_units': totalUnits,
      'unit_price': unitPrice,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      id: map['id'] as String,
      saleId: map['sale_id'] as String,
      itemId: map['item_id'] as String,
      qty: (map['qty'] as num).toDouble(),
      rate: (map['rate'] as num).toDouble(),
      gstRate: (map['gst_rate'] as num).toDouble(),
      gstAmt: (map['gst_amt'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
      manufacturer: map['manufacturer'] as String?,
      packing: map['packing'] as String?,
      batchNo: map['batch_no'] as String?,
      hsnCode: map['hsn_code'] as String?,
      mfgDate: map['mfg_date'] as String?,
      expDate: map['exp_date'] as String?,
      unitPerCase: map['unit_per_case'] != null ? (map['unit_per_case'] as num).toDouble() : null,
      noOfCases: map['no_of_cases'] != null ? (map['no_of_cases'] as num).toDouble() : null,
      totalUnits: map['total_units'] != null ? (map['total_units'] as num).toDouble() : null,
      unitPrice: map['unit_price'] != null ? (map['unit_price'] as num).toDouble() : null,
    );
  }
}
