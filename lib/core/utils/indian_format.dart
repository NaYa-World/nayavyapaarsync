import 'package:intl/intl.dart';

class IndianFormatUtils {
  // Format with Rupee symbol and 2 decimal places: ₹ 1,50,000.00
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹ ',
    decimalDigits: 2,
  );

  // Format with Rupee symbol but no decimal places: ₹ 1,50,000
  static final NumberFormat _currencyFormatNoDecimals = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹ ',
    decimalDigits: 0,
  );

  // Decimal formatting in Indian style (no currency symbol)
  static final NumberFormat _decimalFormat = NumberFormat.decimalPattern('en_IN');

  /// Formats currency with the Rupee symbol and two decimal places (e.g. ₹ 1,50,000.50)
  static String formatCurrency(double amount) {
    return _currencyFormat.format(amount);
  }

  /// Formats currency without decimals (e.g. ₹ 1,50,000)
  static String formatCurrencyNoDecimals(double amount) {
    return _currencyFormatNoDecimals.format(amount);
  }

  /// Formats a generic double/int value in the Indian numbering style (e.g. 1,50,000.25)
  static String formatNumber(double value) {
    // If it's a whole number, represent as integer
    if (value == value.roundToDouble()) {
      return _decimalFormat.format(value.toInt());
    }
    return _decimalFormat.format(value);
  }

  /// Formats quantity with unit display
  /// If item has a bag/box weight, it appends the secondary equivalent weight.
  /// E.g. "3 BAGS", "(150 kg)"
  static String formatQtyWithUnit({
    required double qty,
    required String unit, // 'BAG' or 'BOX'
    double? unitWeightKg,
  }) {
    final String qtyStr = formatNumber(qty);
    final String unitStr = qty == 1 ? unit.toUpperCase() : '${unit.toUpperCase()}S';
    final String primary = '$qtyStr $unitStr';
    
    return primary;
  }
}
