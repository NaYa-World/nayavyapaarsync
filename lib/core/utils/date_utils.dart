import 'package:intl/intl.dart';

class AppDateUtils {
  static final DateFormat _dateFormat = DateFormat('dd-MMM-yyyy');

  /// Formats a DateTime object to 'DD-MMM-YYYY' string (e.g., 13-Jun-2026)
  static String formatDate(DateTime date) {
    return _dateFormat.format(date);
  }

  /// Parses a 'DD-MMM-YYYY' string into a DateTime object
  static DateTime parseDate(String dateStr) {
    return _dateFormat.parse(dateStr);
  }

  /// Formats a DateTime object as ISO8601 string for DB storage
  static String toDbString(DateTime date) {
    return date.toIso8601String();
  }

  /// Parses a database ISO8601 string back to DateTime
  static DateTime fromDbString(String dbStr) {
    return DateTime.parse(dbStr);
  }

  /// Returns the Financial Year string (e.g., "2026-27") for a given date.
  /// Indian Financial Year starts on April 1 and ends on March 31.
  static String getFinancialYear(DateTime date) {
    final int year = date.year;
    final int month = date.month;

    int fyStartYear;
    if (month >= 4) {
      fyStartYear = year;
    } else {
      fyStartYear = year - 1;
    }

    final int fyEndYearSuffix = (fyStartYear + 1) % 100;
    // Format: YYYY-YY (e.g., 2026-27)
    final String endYearStr = fyEndYearSuffix.toString().padLeft(2, '0');
    return '$fyStartYear-$endYearStr';
  }

  /// Returns the start and end date of the Financial Year for a given date
  static DateTimeRange getFinancialYearRange(DateTime date) {
    final int year = date.year;
    final int month = date.month;

    int fyStartYear;
    if (month >= 4) {
      fyStartYear = year;
    } else {
      fyStartYear = year - 1;
    }

    final DateTime start = DateTime(fyStartYear, 4, 1);
    final DateTime end = DateTime(fyStartYear + 1, 3, 31, 23, 59, 59, 999);
    return DateTimeRange(start: start, end: end);
  }
}

class DateTimeRange {
  final DateTime start;
  final DateTime end;

  DateTimeRange({required this.start, required this.end});
}
