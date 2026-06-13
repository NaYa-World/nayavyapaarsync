import 'package:flutter_test/flutter_test.dart';
import 'package:godown_management/core/utils/date_utils.dart';
import 'package:godown_management/core/utils/gst_calculator.dart';
import 'package:godown_management/core/utils/indian_format.dart';
import 'package:godown_management/core/utils/invoice_number.dart';

void main() {
  group('AppDateUtils Tests', () {
    test('Format and parse dates', () {
      final date = DateTime(2026, 6, 13);
      final formatted = AppDateUtils.formatDate(date);
      expect(formatted, '13-Jun-2026');

      final parsed = AppDateUtils.parseDate('13-Jun-2026');
      expect(parsed.year, 2026);
      expect(parsed.month, 6);
      expect(parsed.day, 13);
    });

    test('DB string conversions', () {
      final date = DateTime(2026, 6, 13, 12, 30);
      final dbStr = AppDateUtils.toDbString(date);
      final parsed = AppDateUtils.fromDbString(dbStr);
      expect(parsed, date);
    });

    test('Financial Year computation', () {
      // In June 2026
      expect(AppDateUtils.getFinancialYear(DateTime(2026, 6, 13)), '2026-27');
      // In March 2026 (still previous FY)
      expect(AppDateUtils.getFinancialYear(DateTime(2026, 3, 31)), '2025-26');
      // On April 1, 2026 (starts new FY)
      expect(AppDateUtils.getFinancialYear(DateTime(2026, 4, 1)), '2026-27');
    });

    test('Financial Year range range check', () {
      final range = AppDateUtils.getFinancialYearRange(DateTime(2026, 6, 13));
      expect(range.start, DateTime(2026, 4, 1));
      expect(range.end.year, 2027);
      expect(range.end.month, 3);
      expect(range.end.day, 31);
    });
  });

  group('GstCalculator Tests', () {
    test('Intra-state calculation splits CGST/SGST', () {
      final result = GstCalculator.calculateLineItem(
        qty: 10,
        rate: 100,
        gstRate: 12,
        destinationStateCode: '36', // Telangana
        firmStateCode: '36',        // Telangana
      );
      expect(result.subtotal, 1000.0);
      expect(result.gstAmount, 120.0);
      expect(result.cgstAmount, 60.0);
      expect(result.sgstAmount, 60.0);
      expect(result.igstAmount, 0.0);
      expect(result.total, 1120.0);
    });

    test('Inter-state calculation uses IGST', () {
      final result = GstCalculator.calculateLineItem(
        qty: 10,
        rate: 100,
        gstRate: 12,
        destinationStateCode: '37', // Andhra Pradesh
        firmStateCode: '36',        // Telangana
      );
      expect(result.subtotal, 1000.0);
      expect(result.gstAmount, 120.0);
      expect(result.cgstAmount, 0.0);
      expect(result.sgstAmount, 0.0);
      expect(result.igstAmount, 120.0);
      expect(result.total, 1120.0);
    });

    test('Invoice tax breakup summary', () {
      final items = [
        {'qty': 2.0, 'rate': 500.0, 'gstRate': 12.0},
        {'qty': 1.0, 'rate': 1000.0, 'gstRate': 5.0},
      ];
      final breakup = GstCalculator.calculateInvoiceBreakup(
        items: items,
        destinationStateCode: '36',
        firmStateCode: '36',
      );

      expect(breakup.subtotal, 2000.0);
      expect(breakup.gstTotal, 170.0); // 120 (12% of 1000) + 50 (5% of 1000)
      expect(breakup.cgstTotal, 85.0);
      expect(breakup.sgstTotal, 85.0);
      expect(breakup.grandTotal, 2170.0);

      expect(breakup.rateSummary.containsKey(12.0), true);
      expect(breakup.rateSummary.containsKey(5.0), true);
    });

    test('Default GST rates by category', () {
      expect(GstCalculator.getDefaultGstRate('Fertiliser'), 0.0);
      expect(GstCalculator.getDefaultGstRate('Seed', isBranded: false), 0.0);
      expect(GstCalculator.getDefaultGstRate('Seed', isBranded: true), 5.0);
    });
  });

  group('IndianFormatUtils Tests', () {
    test('Currency formatting', () {
      // Clean standard spaces & rupee symbol format checks
      expect(IndianFormatUtils.formatCurrency(150000.50).replaceAll('\u00A0', ' '), '₹ 1,50,000.50');
      expect(IndianFormatUtils.formatCurrencyNoDecimals(150000).replaceAll('\u00A0', ' '), '₹ 1,50,000');
    });

    test('Number formatting', () {
      expect(IndianFormatUtils.formatNumber(150000.0), '1,50,000');
      expect(IndianFormatUtils.formatNumber(1500.5), '1,500.5');
    });

    test('Quantity with units', () {
      expect(IndianFormatUtils.formatQtyWithUnit(qty: 3, unit: 'bag'), '3 BAGS');
      expect(IndianFormatUtils.formatQtyWithUnit(qty: 1, unit: 'box'), '1 BOX');
    });
  });

  group('InvoiceNumberGenerator Tests', () {
    test('Generate and parse invoice numbers', () {
      final generated = InvoiceNumberGenerator.generate(
        type: 'SAL',
        financialYear: '2026-27',
        sequenceNumber: 15,
      );
      expect(generated, 'SAL/2026-27/015');

      final parsed = InvoiceNumberGenerator.parse('SAL/2026-27/015');
      expect(parsed, isNotNull);
      expect(parsed!['type'], 'SAL');
      expect(parsed['financialYear'], '2026-27');
      expect(parsed['sequence'], 15);

      final invalid = InvoiceNumberGenerator.parse('SAL/2026-27');
      expect(invalid, isNull);
    });
  });
}
