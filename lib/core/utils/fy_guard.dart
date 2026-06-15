import '../../data/database/db_helper.dart';
import '../../data/models/financial_year.dart';

/// Exception thrown when a voucher date falls in a locked financial year.
class LockedPeriodException implements Exception {
  final FinancialYear lockedFY;
  LockedPeriodException(this.lockedFY);

  @override
  String toString() =>
      'Period locked: ${lockedFY.label} is locked and cannot accept new entries.';
}

/// Guard utility to validate voucher dates against locked financial years.
///
/// Usage (in any repository before INSERT/UPDATE):
/// ```dart
/// await FyGuard.checkDate(companyId: companyId, date: voucherDate);
/// ```
class FyGuard {
  FyGuard._(); // static only

  static final DbHelper _db = DbHelper();

  /// Checks if [date] falls in a locked financial year for [companyId].
  ///
  /// If companyId is null (legacy single-company mode), check is skipped.
  /// Throws [LockedPeriodException] if the period is locked.
  static Future<void> checkDate({
    required DateTime date,
    String? companyId,
  }) async {
    // If no company context, skip guard (backward compatibility)
    if (companyId == null) return;

    final db = await _db.database;
    final dateStr = date.toIso8601String().substring(0, 10);

    final rows = await db.query(
      'financial_years',
      where:
          'company_id = ? AND start_date <= ? AND end_date >= ? AND is_locked = 1',
      whereArgs: [companyId, dateStr, dateStr],
    );

    if (rows.isNotEmpty) {
      final lockedFY = FinancialYear.fromMap(rows.first);
      throw LockedPeriodException(lockedFY);
    }
  }

  /// Returns true if [date] is in a locked FY for [companyId].
  /// Use this for UI to pre-check before showing a form.
  static Future<bool> isDateLocked({
    required DateTime date,
    String? companyId,
  }) async {
    if (companyId == null) return false;
    try {
      await checkDate(date: date, companyId: companyId);
      return false;
    } on LockedPeriodException {
      return true;
    }
  }
}
