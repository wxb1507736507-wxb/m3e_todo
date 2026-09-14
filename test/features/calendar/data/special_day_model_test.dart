import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/calendar/data/models/special_day_model.dart';
import 'package:m3e_todo/features/calendar/domain/entities/special_day.dart';

void main() {
  group('round trip', () {
    test('preserves every field', () {
      final SpecialDay original = SpecialDay.create(
        id: 'd1',
        title: '结婚纪念日',
        kind: SpecialDayKind.anniversary,
        date: DateTime(2021, 6, 1),
        notes: '订餐厅',
      );

      final Map<String, Object?> json = SpecialDayModel.toJson(original);

      expect(json['kind'], 'anniversary');
      expect(SpecialDayModel.fromJson(json), original);
    });

    test('omits absent optional fields rather than writing nulls', () {
      final Map<String, Object?> json = SpecialDayModel.toJson(
        SpecialDay.create(
          id: 'd1',
          title: '考试',
          kind: SpecialDayKind.countdown,
          date: DateTime(2026, 3, 20),
        ),
      );

      expect(json.containsKey('notes'), isFalse);
    });
  });

  group('resilience', () {
    Map<String, Object?> valid() => <String, Object?>{
          'id': 'd1',
          'title': '妈妈生日',
          'kind': 'birthday',
          'date': '1996-10-03T00:00:00.000',
        };

    test('rejects a record with no id', () {
      final Map<String, Object?> json = valid()..remove('id');
      expect(SpecialDayModel.fromJson(json), isNull);
    });

    test('rejects a blank title', () {
      final Map<String, Object?> json = valid()..['title'] = '  ';
      expect(SpecialDayModel.fromJson(json), isNull);
    });

    test('rejects an unparsable date', () {
      final Map<String, Object?> json = valid()..['date'] = 'not-a-date';
      expect(SpecialDayModel.fromJson(json), isNull);
    });

    test('an unknown kind is read as a yearly date', () {
      // A kind from a future version must not cost the record, and a yearly
      // reading still puts it on the right day.
      final Map<String, Object?> json = valid()..['kind'] = 'name-day';
      expect(
        SpecialDayModel.fromJson(json)?.kind,
        SpecialDayKind.anniversary,
      );
    });

    test('ignores fields it does not know about', () {
      final Map<String, Object?> json = valid()..['futureField'] = 42;
      expect(SpecialDayModel.fromJson(json), isNotNull);
    });
  });
}
