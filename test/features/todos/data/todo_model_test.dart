import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/notifications/domain/reminder.dart';
import 'package:m3e_todo/features/todos/data/models/todo_model.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_attachment.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_priority.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_reminder.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_subtask.dart';

import '../../../support/sample_todo.dart';

void main() {
  group('round trip', () {
    test('preserves every field', () {
      final Todo original = Todo(
        id: 'abc',
        title: '评审设计稿',
        createdAt: DateTime(2026, 3, 1, 9, 30),
        notes: '带上原型',
        priority: TodoPriority.high,
        dueDate: DateTime(2026, 3, 12),
        completedAt: DateTime(2026, 3, 11, 16),
      );

      final Todo restored = TodoModel.fromJson(TodoModel.toJson(original))!;

      expect(restored, original);
    });

    test('preserves a todo with no optional fields set', () {
      final Todo original = sampleTodo();
      final Todo restored = TodoModel.fromJson(TodoModel.toJson(original))!;
      expect(restored, original);
      expect(restored.notes, isNull);
      expect(restored.dueDate, isNull);
      expect(restored.completedAt, isNull);
    });

    test('omits absent optional fields rather than writing nulls', () {
      final Map<String, Object?> json = TodoModel.toJson(sampleTodo());
      expect(json.containsKey('notes'), isFalse);
      expect(json.containsKey('dueDate'), isFalse);
      expect(json.containsKey('completedAt'), isFalse);
      expect(json.containsKey('textColor'), isFalse);
    });

    test('carries both colours through the file', () {
      final Todo original = sampleTodo().edit(
        title: '带颜色的待办',
        notes: null,
        priority: TodoPriority.normal,
        dueDate: null,
        subtasks: const <TodoSubtask>[],
        attachments: const <TodoAttachment>[],
        accentColor: 0xFF1E88E5,
        textColor: 0xFFFDD835,
        backgroundImage: null,
        reminder: TodoReminder.followApp,
        ringtoneUri: null,
        reminderLead: null,
        categoryId: null,
      );

      final Map<String, Object?> json = TodoModel.toJson(original);
      expect(json['accentColor'], 0xFF1E88E5);
      expect(json['textColor'], 0xFFFDD835);
      expect(TodoModel.fromJson(json), original);
    });

    test('a file written before text colours existed still loads', () {
      // Shape of a version-2 record: no `textColor` key at all.
      final Map<String, Object?> version2 = <String, Object?>{
        'id': 'old',
        'title': '旧版本写的',
        'createdAt': '2026-03-01T09:30:00.000',
        'priority': 'normal',
        'accentColor': 0xFF43A047,
      };

      final Todo restored = TodoModel.fromJson(version2)!;

      expect(restored.accentColor, 0xFF43A047);
      expect(restored.textColor, isNull);
    });

    test('a non-integer colour is ignored rather than crashing the record', () {
      final Map<String, Object?> broken = <String, Object?>{
        'id': 'a',
        'title': '标题',
        'createdAt': '2026-03-01T09:30:00.000',
        'textColor': 'red',
      };

      expect(TodoModel.fromJson(broken)?.textColor, isNull);
    });

    test('carries a per-todo reminder, ringtone and lead through the file', () {
      final Todo original = sampleTodo().edit(
        title: '要响的',
        notes: null,
        priority: TodoPriority.high,
        dueDate: DateTime(2026, 4, 1),
        subtasks: const <TodoSubtask>[],
        attachments: const <TodoAttachment>[],
        accentColor: null,
        textColor: null,
        backgroundImage: null,
        reminder: TodoReminder.ring,
        ringtoneUri: 'content://media/internal/audio/media/42',
        reminderLead: ReminderLead.threeDays,
        categoryId: null,
      );

      final Map<String, Object?> json = TodoModel.toJson(original);
      expect(json['reminder'], 'ring');
      expect(json['ringtoneUri'], 'content://media/internal/audio/media/42');
      expect(json['reminderLead'], 'threeDays');
      expect(TodoModel.fromJson(json), original);
    });

    test('following the app setting is written by leaving the key out', () {
      final Map<String, Object?> json = TodoModel.toJson(sampleTodo());
      expect(json.containsKey('reminder'), isFalse);
      expect(json.containsKey('ringtoneUri'), isFalse);
      expect(TodoModel.fromJson(json)?.reminder, TodoReminder.followApp);
    });

    test('a file written before reminders existed still loads', () {
      // Shape of a version-3 record: no reminder keys at all.
      final Map<String, Object?> version3 = <String, Object?>{
        'id': 'old',
        'title': '旧版本写的',
        'createdAt': '2026-03-01T09:30:00.000',
        'priority': 'normal',
        'dueDate': '2026-04-01T00:00:00.000',
      };

      final Todo restored = TodoModel.fromJson(version3)!;

      expect(restored.reminder, TodoReminder.followApp);
      expect(restored.ringtoneUri, isNull);
    });

    test('an unknown reminder name is read as following the app setting', () {
      // A name from a future version must not cost the user the record, and
      // following the default is the harmless reading of one we cannot parse.
      final Map<String, Object?> json = <String, Object?>{
        'id': 'a',
        'title': '标题',
        'createdAt': '2026-03-01T09:30:00.000',
        'reminder': 'vibrate-twice',
      };

      expect(TodoModel.fromJson(json)?.reminder, TodoReminder.followApp);
    });
  });

  group('fromJson resilience', () {
    Map<String, Object?> valid() => <String, Object?>{
          'id': 'a',
          'title': '任务',
          'createdAt': '2026-03-01T10:00:00.000',
        };

    test('rejects a record with no id', () {
      final Map<String, Object?> json = valid()..remove('id');
      expect(TodoModel.fromJson(json), isNull);
    });

    test('rejects a record with a blank title', () {
      final Map<String, Object?> json = valid()..['title'] = '   ';
      expect(TodoModel.fromJson(json), isNull);
    });

    test('rejects a record whose createdAt is unparsable', () {
      final Map<String, Object?> json = valid()..['createdAt'] = 'not-a-date';
      expect(TodoModel.fromJson(json), isNull);
    });

    test('falls back to normal priority for an unknown value', () {
      final Map<String, Object?> json = valid()..['priority'] = 'urgent';
      expect(TodoModel.fromJson(json)?.priority, TodoPriority.normal);
    });

    test('still loads a record whose optional date is corrupt', () {
      final Map<String, Object?> json = valid()..['dueDate'] = 'nonsense';
      final Todo? todo = TodoModel.fromJson(json);
      expect(todo, isNotNull);
      expect(todo!.dueDate, isNull);
    });

    test('ignores fields it does not know about', () {
      final Map<String, Object?> json = valid()..['futureField'] = 42;
      expect(TodoModel.fromJson(json), isNotNull);
    });
  });
}
