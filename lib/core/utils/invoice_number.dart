class InvoiceNumberGenerator {
  /// Generates the invoice number string: e.g., SAL/2026-27/001 or PUR/2026-27/001
  static String generate({
    required String type, // 'PUR' or 'SAL'
    required String financialYear, // e.g. '2026-27'
    required int sequenceNumber, // 1, 2, 3...
  }) {
    final String sequenceStr = sequenceNumber.toString().padLeft(3, '0');
    return '$type/$financialYear/$sequenceStr';
  }

  /// Parses an invoice number into its components (type, FY, sequence)
  /// Returns null if format does not match.
  static Map<String, dynamic>? parse(String invoiceNo) {
    final parts = invoiceNo.split('/');
    if (parts.length != 3) return null;

    final String type = parts[0];
    final String fy = parts[1];
    final int? sequence = int.tryParse(parts[2]);

    if ((type != 'PUR' && type != 'SAL') || sequence == null) {
      return null;
    }

    return {
      'type': type,
      'financialYear': fy,
      'sequence': sequence,
    };
  }
}
