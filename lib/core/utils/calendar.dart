/// Calendar helpers that ignore the time component.
///
/// Due dates are day-granular: a task is due *on a day*, not at a moment. All
/// comparisons therefore normalise to midnight first, which avoids the classic
/// bug where a task due "today" is reported as overdue at 00:01.
library;

/// Midnight at the start of [value]'s day, in local time.
DateTime startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// Whole days from [from] to [to], counted by calendar day rather than by
/// elapsed hours.
///
/// Positive when [to] is later, zero for the same day, negative when [to] is
/// earlier.
int daysBetween(DateTime from, DateTime to) {
  return startOfDay(to).difference(startOfDay(from)).inDays;
}

/// Whether [a] and [b] fall on the same calendar day.
bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Whether [value] is strictly before today.
bool isBeforeToday(DateTime value, DateTime now) {
  return startOfDay(value).isBefore(startOfDay(now));
}

/// Whether [value] falls on today's date.
bool isToday(DateTime value, DateTime now) => isSameDay(value, now);

/// Whether [value] falls on tomorrow's date.
bool isTomorrow(DateTime value, DateTime now) {
  return isSameDay(value, startOfDay(now).add(const Duration(days: 1)));
}
