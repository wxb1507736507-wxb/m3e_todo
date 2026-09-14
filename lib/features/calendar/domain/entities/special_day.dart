import 'dart:math' as math;

import '../../../../core/utils/calendar.dart';

/// What kind of personal date this is.
///
/// The kind decides whether it comes round every year, which is the only
/// difference that matters to the maths — and it is what the user is really
/// choosing between: a birthday and an anniversary recur, a countdown runs out
/// once.
enum SpecialDayKind {
  birthday(repeatsYearly: true),
  anniversary(repeatsYearly: true),
  countdown(repeatsYearly: false);

  const SpecialDayKind({required this.repeatsYearly});

  final bool repeatsYearly;
}

/// A date worth remembering that is not a task: a birthday, an anniversary, or
/// a countdown to something.
///
/// Deliberately *not* a [Todo]: nothing here is completed, ticked off or
/// overdue. A birthday you cannot finish, and a list that mixes the two makes
/// both harder to read — so these live in their own collection and show up on
/// the calendar beside the tasks.
///
/// Immutable, like everything else in the domain.
class SpecialDay {
  const SpecialDay({
    required this.id,
    required this.title,
    required this.kind,
    required this.date,
    this.notes,
  });

  /// Builds one from raw input, normalising as the domain requires: a trimmed
  /// non-blank title, and a date reduced to midnight.
  factory SpecialDay.create({
    required String id,
    required String title,
    required SpecialDayKind kind,
    required DateTime date,
    String? notes,
  }) {
    final String normalized = title.trim();
    if (normalized.isEmpty) {
      throw const SpecialDayValidationException('A special day needs a title.');
    }
    return SpecialDay(
      id: id,
      title: normalized,
      kind: kind,
      date: startOfDay(date),
      notes: _normalizeNotes(notes),
    );
  }

  final String id;
  final String title;
  final SpecialDayKind kind;

  /// The anchor date: the day itself for a birthday or anniversary, the target
  /// day for a countdown. Always midnight, local time.
  final DateTime date;

  final String? notes;

  bool get repeatsYearly => kind.repeatsYearly;

  /// month * 100 + day, the identity a yearly date keeps across years.
  ///
  /// The grid marks a recurring date by this rather than by its stored year, so
  /// a birthday entered once shows up on every year's calendar.
  int get monthDayKey => date.month * 100 + date.day;

  /// The next time this day comes round, on or after [now].
  ///
  /// A yearly date that has already passed this year rolls to next year, so the
  /// caller always gets a date to count down to. A one-off countdown has no next
  /// occurrence: its own date is the answer, past or future, because "3 days
  /// ago" is information and next year's same date is not.
  DateTime nextOccurrence(DateTime now) {
    if (!repeatsYearly) {
      return date;
    }
    final DateTime today = startOfDay(now);
    final DateTime thisYear = _inYear(today.year);
    if (thisYear.isBefore(today)) {
      return _inYear(today.year + 1);
    }
    return thisYear;
  }

  /// Whole days from today until [nextOccurrence]; `0` means today.
  ///
  /// Negative only for a one-off countdown whose target has passed.
  int daysUntil(DateTime now) => daysBetween(now, nextOccurrence(now));

  /// Which anniversary this is: `1` on the first, and so on.
  ///
  /// `null` for a countdown, where "the 5th time" means nothing. For a yearly
  /// date the years between the anchor and the *next* occurrence is exactly the
  /// number the user is counting.
  int? ordinal(DateTime now) {
    if (!repeatsYearly) {
      return null;
    }
    final int years = nextOccurrence(now).year - date.year;
    return years > 0 ? years : null;
  }

  /// The same day with the user's edits applied.
  SpecialDay edit({
    required String title,
    required SpecialDayKind kind,
    required DateTime date,
    required String? notes,
  }) {
    final String normalized = title.trim();
    if (normalized.isEmpty) {
      throw const SpecialDayValidationException('A special day needs a title.');
    }
    return SpecialDay(
      id: id,
      title: normalized,
      kind: kind,
      date: startOfDay(date),
      notes: _normalizeNotes(notes),
    );
  }

  /// This day shifted into [year], keeping its month and day.
  ///
  /// A 29 February birthday in a common year is observed on the 28th instead of
  /// vanishing for three years out of four.
  DateTime _inYear(int year) {
    final int lastDay = DateTime(year, date.month + 1, 0).day;
    return DateTime(year, date.month, math.min(date.day, lastDay));
  }

  @override
  bool operator ==(Object other) =>
      other is SpecialDay &&
      other.id == id &&
      other.title == title &&
      other.kind == kind &&
      other.date == date &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(id, title, kind, date, notes);

  @override
  String toString() => 'SpecialDay($id, "$title", ${kind.name}, $date)';

  static String? _normalizeNotes(String? notes) {
    final String trimmed = notes?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Thrown when a special day would break the rule that a title is required.
class SpecialDayValidationException implements Exception {
  const SpecialDayValidationException(this.message);

  final String message;

  @override
  String toString() => 'SpecialDayValidationException: $message';
}

/// Orders personal dates the way a calendar would: whatever comes next first,
/// and the ones already past at the end.
///
/// A countdown that has run out is finished, not urgent — listing "5 days ago"
/// above "in 3 days" would bury the thing still to come under the thing that is
/// already over. Ties fall back to the title, so the order never wobbles between
/// builds.
int compareSpecialDays(SpecialDay a, SpecialDay b, DateTime now) {
  final int daysA = a.daysUntil(now);
  final int daysB = b.daysUntil(now);
  final bool passedA = daysA < 0;
  final bool passedB = daysB < 0;
  if (passedA != passedB) {
    return passedA ? 1 : -1;
  }
  // Upcoming: soonest first. Past: most recently passed first.
  final int byDays = passedA ? daysB.compareTo(daysA) : daysA.compareTo(daysB);
  return byDays != 0 ? byDays : a.title.compareTo(b.title);
}
