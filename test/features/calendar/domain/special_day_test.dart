import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/calendar/domain/entities/special_day.dart';

/// The day everything is judged against: 10 March 2026.
final DateTime now = DateTime(2026, 3, 10, 9, 30);

SpecialDay day({
  String title = '妈妈生日',
  SpecialDayKind kind = SpecialDayKind.birthday,
  DateTime? date,
  String? notes,
}) {
  return SpecialDay.create(
    id: 'd1',
    title: title,
    kind: kind,
    date: date ?? DateTime(1996, 10, 3),
    notes: notes,
  );
}

void main() {
  group('creation', () {
    test('trims the title and rejects a blank one', () {
      expect(day(title: '  妈妈生日  ').title, '妈妈生日');
      expect(
        () => day(title: '   '),
        throwsA(isA<SpecialDayValidationException>()),
      );
    });

    test('reduces the date to midnight', () {
      expect(day(date: DateTime(1996, 10, 3, 17, 45)).date, DateTime(1996, 10, 3));
    });

    test('collapses empty notes to null', () {
      expect(day(notes: '   ').notes, isNull);
      expect(day(notes: ' 记得买蛋糕 ').notes, '记得买蛋糕');
    });
  });

  group('yearly dates', () {
    test('a day later this year counts down to it in this year', () {
      final SpecialDay birthday = day(); // 3 October
      expect(birthday.nextOccurrence(now), DateTime(2026, 10, 3));
      expect(birthday.daysUntil(now), 207);
    });

    test('a day already past this year rolls to the next one', () {
      final SpecialDay passed = day(date: DateTime(1996, 2, 1));
      expect(passed.nextOccurrence(now), DateTime(2027, 2, 1));
      expect(passed.daysUntil(now), greaterThan(300));
    });

    test('the day itself is zero days away, not a year', () {
      final SpecialDay today = day(date: DateTime(1996, 3, 10));
      expect(today.nextOccurrence(now), DateTime(2026, 3, 10));
      expect(today.daysUntil(now), 0);
    });

    test('a 29 February birthday lands on the 28th in a common year', () {
      // Observed rather than skipped: a birthday that vanishes three years in
      // four is worse than one a day early.
      final SpecialDay leap = day(date: DateTime(2000, 2, 29));
      expect(leap.nextOccurrence(DateTime(2026, 1, 5)), DateTime(2026, 2, 28));

      final SpecialDay leapYear = day(date: DateTime(2000, 2, 29));
      expect(leapYear.nextOccurrence(DateTime(2028, 1, 1)), DateTime(2028, 2, 29));
    });

    test('the month-and-day key is what the grid marks', () {
      expect(day().monthDayKey, 1003);
    });

    test('the years counted are the ones being celebrated', () {
      // Born 1996: the next 3rd of October is their 30th.
      expect(day().ordinal(now), 30);
      // Married in 2021: the next 1st of June is the fifth anniversary.
      expect(
        day(kind: SpecialDayKind.anniversary, date: DateTime(2021, 6, 1))
            .ordinal(now),
        5,
      );
    });

    test('a date with no years behind it reports no ordinal', () {
      expect(day(date: DateTime(2026, 10, 3)).ordinal(now), isNull);
    });
  });

  group('countdowns', () {
    test('count down to the target', () {
      final SpecialDay target = day(
        title: '考试',
        kind: SpecialDayKind.countdown,
        date: DateTime(2026, 3, 20),
      );
      expect(target.daysUntil(now), 10);
      expect(target.nextOccurrence(now), DateTime(2026, 3, 20));
      expect(target.ordinal(now), isNull);
    });

    test('go negative once the target has passed', () {
      // Not rolled forward: "3 days ago" is information, next year's same date
      // is not.
      final SpecialDay gone = day(
        title: '考试',
        kind: SpecialDayKind.countdown,
        date: DateTime(2026, 3, 7),
      );
      expect(gone.daysUntil(now), -3);
      expect(gone.nextOccurrence(now), DateTime(2026, 3, 7));
    });
  });

  group('editing', () {
    test('keeps identity and applies every field', () {
      final SpecialDay edited = day().edit(
        title: '爸爸生日',
        kind: SpecialDayKind.anniversary,
        date: DateTime(2020, 5, 1),
        notes: '订花',
      );

      expect(edited.id, 'd1');
      expect(edited.title, '爸爸生日');
      expect(edited.kind, SpecialDayKind.anniversary);
      expect(edited.date, DateTime(2020, 5, 1));
      expect(edited.notes, '订花');
    });

    test('rejects a blank title', () {
      expect(
        () => day().edit(
          title: ' ',
          kind: SpecialDayKind.birthday,
          date: DateTime(1996, 10, 3),
          notes: null,
        ),
        throwsA(isA<SpecialDayValidationException>()),
      );
    });
  });

  test('value equality covers every field', () {
    expect(day(), day());
    expect(day(), isNot(day(title: '别人的生日')));
    expect(day(), isNot(day(kind: SpecialDayKind.anniversary)));
  });
}
