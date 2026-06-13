class GstCalculationResult {
  final double subtotal;
  final double gstRate;
  final double gstAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double total;

  GstCalculationResult({
    required this.subtotal,
    required this.gstRate,
    required this.gstAmount,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.total,
  });
}

class InvoiceTaxBreakup {
  final double subtotal;
  final double gstTotal;
  final double cgstTotal;
  final double sgstTotal;
  final double igstTotal;
  final double grandTotal;
  final Map<double, GstRateSummary> rateSummary; // GST Rate -> Summary

  InvoiceTaxBreakup({
    required this.subtotal,
    required this.gstTotal,
    required this.cgstTotal,
    required this.sgstTotal,
    required this.igstTotal,
    required this.grandTotal,
    required this.rateSummary,
  });
}

class GstRateSummary {
  final double taxableAmount;
  final double gstAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;

  GstRateSummary({
    required this.taxableAmount,
    required this.gstAmount,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
  });
}

class GstCalculator {
  static const String telanganaStateCode = '36';

  /// Calculates GST for a single line item
  static GstCalculationResult calculateLineItem({
    required double qty,
    required double rate,
    required double gstRate, // e.g. 5.0, 12.0
    required String destinationStateCode, // Default is '36' for Telangana
    required String firmStateCode,
  }) {
    final double subtotal = qty * rate;
    final double gstAmount = subtotal * (gstRate / 100.0);

    double cgst = 0.0;
    double sgst = 0.0;
    double igst = 0.0;

    // If both state codes match, it's intra-state: split into CGST & SGST
    if (destinationStateCode == firmStateCode) {
      cgst = gstAmount / 2.0;
      sgst = gstAmount / 2.0;
    } else {
      igst = gstAmount;
    }

    final double total = subtotal + gstAmount;

    return GstCalculationResult(
      subtotal: subtotal,
      gstRate: gstRate,
      gstAmount: gstAmount,
      cgstAmount: cgst,
      sgstAmount: sgst,
      igstAmount: igst,
      total: total,
    );
  }

  /// Calculates invoice tax breakup across all items
  static InvoiceTaxBreakup calculateInvoiceBreakup({
    required List<Map<String, dynamic>> items, // keys: qty (double), rate (double), gstRate (double)
    required String destinationStateCode,
    required String firmStateCode,
  }) {
    double overallSubtotal = 0.0;
    double overallGstTotal = 0.0;
    double overallCgstTotal = 0.0;
    double overallSgstTotal = 0.0;
    double overallIgstTotal = 0.0;
    double overallGrandTotal = 0.0;

    final Map<double, GstRateSummary> rateSummary = {};

    for (final item in items) {
      final double qty = (item['qty'] as num).toDouble();
      final double rate = (item['rate'] as num).toDouble();
      final double gstRate = (item['gstRate'] as num).toDouble();

      final result = calculateLineItem(
        qty: qty,
        rate: rate,
        gstRate: gstRate,
        destinationStateCode: destinationStateCode,
        firmStateCode: firmStateCode,
      );

      overallSubtotal += result.subtotal;
      overallGstTotal += result.gstAmount;
      overallCgstTotal += result.cgstAmount;
      overallSgstTotal += result.sgstAmount;
      overallIgstTotal += result.igstAmount;
      overallGrandTotal += result.total;

      // Update rate summary
      if (rateSummary.containsKey(gstRate)) {
        final existing = rateSummary[gstRate]!;
        rateSummary[gstRate] = GstRateSummary(
          taxableAmount: existing.taxableAmount + result.subtotal,
          gstAmount: existing.gstAmount + result.gstAmount,
          cgstAmount: existing.cgstAmount + result.cgstAmount,
          sgstAmount: existing.sgstAmount + result.sgstAmount,
          igstAmount: existing.igstAmount + result.igstAmount,
        );
      } else {
        rateSummary[gstRate] = GstRateSummary(
          taxableAmount: result.subtotal,
          gstAmount: result.gstAmount,
          cgstAmount: result.cgstAmount,
          sgstAmount: result.sgstAmount,
          igstAmount: result.igstAmount,
        );
      }
    }

    return InvoiceTaxBreakup(
      subtotal: overallSubtotal,
      gstTotal: overallGstTotal,
      cgstTotal: overallCgstTotal,
      sgstTotal: overallSgstTotal,
      igstTotal: overallIgstTotal,
      grandTotal: overallGrandTotal,
      rateSummary: rateSummary,
    );
  }

  /// Default GST rate by category
  static double getDefaultGstRate(String category, {bool isBranded = false}) {
    if (category.toUpperCase() == 'FERTILISER') {
      return 0.0; // Fertilisers default to 0% (exempt)
    } else if (category.toUpperCase() == 'SEED') {
      return isBranded ? 5.0 : 0.0; // Seeds default to 0% (5% if branded)
    }
    return 0.0;
  }
}
