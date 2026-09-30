/// Stable local-date key used for day-granular records.
///
/// Format is `yyyy-MM-dd` in local time, so a rest day declared at 23:50 and a
/// check-in at 00:10 land on different days, as the user would expect.
String dayKey(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Strips the time component, keeping the local calendar date.
DateTime dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}
