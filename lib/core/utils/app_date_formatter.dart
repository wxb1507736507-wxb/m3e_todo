import '../constants/app_strings.dart';
import 'calendar.dart';

/// Formats day-granular dates for display.
///
/// Hand-rolled rather than pulled from `package:intl`: the app only needs
/// relative day labels in one language, and avoiding the dependency keeps the
/// tree small. If the app grows real localisation, this class is the single
/// place that has to be replaced.
abstract final class AppDateFormatter {
  /// A short, human label for [date] relative to [now].
  ///
  /// Today and tomorrow become words because that is how people say them; every
  /// other day is written out, with the year included only when it differs from
  /// the current one. Past days are deliberately not given special wording &mdash;
  /// whether something is late is a judgement the caller makes (see
  /// `Todo.isOverdue`), not something a date formatter should decide.
  static String dayLabel(DateTime date, DateTime now) {
    final int offset = daysBetween(now, date);
    return switch (offset) {
      0 => AppStrings.dueToday,
      1 => AppStrings.dueTomorrow,
      _ => calendarDate(date, now),
    };
  }

  /// The calendar date without any relative wording.
  static String calendarDate(DateTime date, DateTime now) {
    if (date.year == now.year) {
      return '${date.month}月${date.day}日';
    }
    return '${date.year}年${date.month}月${date.day}日';
  }

  /// The span a week covers, as a timetable header says it: `9月14日 - 9月20日`.
  ///
  /// Both ends are written out rather than abbreviated to one, because the week
  /// that straddles a month — 30日 to 10月6日 — is exactly where a single month
  /// name would be wrong.
  static String weekRange(DateTime monday, DateTime sunday) =>
      '${calendarDate(monday, monday)} - ${calendarDate(sunday, monday)}';
}
