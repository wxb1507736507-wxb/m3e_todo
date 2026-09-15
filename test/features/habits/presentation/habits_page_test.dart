import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/habits/domain/entities/habit.dart';
import 'package:m3e_todo/features/habits/domain/entities/habit_log.dart';
import 'package:m3e_todo/features/habits/presentation/widgets/habit_checkin_sheet.dart';
import 'package:m3e_todo/features/habits/presentation/widgets/habit_editor_sheet.dart';

import '../../../support/fake_habit_repository.dart';
import '../../../support/fake_todo_repository.dart';
import '../../../support/sample_todo.dart' show testNow;
import '../../../support/test_app.dart';

/// The 打卡 destination: adding a habit, checking it off, and the records left
/// behind.
void main() {
  Habit habit(
    String id, {
    String name = '吃药',
    int days = kHabitEveryDay,
    int? reminderMinutes,
    bool allowNote = true,
  }) {
    return Habit.create(
      id: id,
      name: name,
      emoji: '💊',
      days: days,
      createdAt: DateTime(2026, 3, 1),
      reminderMinutes: reminderMinutes,
      allowNote: allowNote,
    );
  }

  Future<void> openHabits(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(AppStrings.navHabits),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the habits destination says what it is for when empty', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: FakeHabitRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    expect(find.text(AppStrings.habitEmptyTitle), findsOneWidget);
    expect(find.text(AppStrings.habitEmptyBody), findsOneWidget);
  });

  testWidgets('today\'s habits are listed, and only today\'s', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: FakeHabitRepository(
          habits: <Habit>[
            habit('daily'),
            // A habit due on one weekday only: testNow is a Tuesday, so a
            // Monday-only habit belongs under "其他打卡项" instead of today.
            habit('mondays', name: '周一瑜伽', days: habitDayBit(DateTime.monday)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    expect(find.text('吃药'), findsOneWidget);
    expect(find.text('周一瑜伽'), findsOneWidget);
    // Both are on screen, but only the due one is under today's heading.
    expect(find.text(AppStrings.habitToday), findsOneWidget);
    expect(find.text(AppStrings.habitOthers), findsOneWidget);
    expect(find.text(AppStrings.habitTodayNone), findsNothing);
  });

  testWidgets('the circle checks a habit off, and takes it back', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeHabitRepository repository = FakeHabitRepository(
      habits: <Habit>[habit('h1')],
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pumpAndSettle();

    final List<HabitLog> logs = await repository.loadLogs();
    expect(logs, hasLength(1));
    expect(logs.single.habitId, 'h1');
    // Checked off for the day the app thinks it is, not for "now" in some other
    // shape: everything about a habit is day-granular.
    expect(logs.single.dayKey, habitDayKey(testNow));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pumpAndSettle();
    expect(await repository.loadLogs(), isEmpty);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  testWidgets('a habit can be added and named from the destination', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeHabitRepository repository = FakeHabitRepository();
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(HabitEditorSheet), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '喝水');
    await tester.tap(find.text(AppStrings.create));
    await tester.pumpAndSettle();

    final List<Habit> stored = await repository.loadHabits();
    expect(stored.single.name, '喝水');
    // "每天" is the default a new habit starts from, so a habit needs no
    // schedule decisions to be usable.
    expect(stored.single.days, kHabitEveryDay);
    // And no reminder until one is asked for.
    expect(stored.single.reminderMinutes, isNull);
    expect(find.text('喝水'), findsOneWidget);
  });

  testWidgets('the editor refuses a habit with no days selected', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeHabitRepository repository = FakeHabitRepository(
      habits: <Habit>[habit('h1', days: habitDayBit(DateTime.monday))],
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.habitEdit));
    await tester.pumpAndSettle();

    // Turn its only day off: a habit that is never due asks nothing of anyone,
    // and would sit in the list for ever.
    final Finder monday = find.descendant(
      of: find.byType(HabitEditorSheet),
      matching: find.text(kHabitWeekdayNames[0]),
    );
    await tester.ensureVisible(monday);
    await tester.pumpAndSettle();
    await tester.tap(monday);
    await tester.pumpAndSettle();

    final Finder save = find.descendant(
      of: find.byType(HabitEditorSheet),
      matching: find.text(AppStrings.save),
    );
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.habitDaysRequired), findsOneWidget);
    // Nothing was written, and the editor is still open for the user to fix.
    expect((await repository.loadHabits()).single.days, habitDayBit(DateTime.monday));
    expect(find.byType(HabitEditorSheet), findsOneWidget);
  });

  testWidgets('a check-in can carry a note, and keeps it', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeHabitRepository repository = FakeHabitRepository(
      habits: <Habit>[habit('h1', name: '喝水')],
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    // The row opens the editor, which is where a note can be written: the
    // circle is the one-tap path, this is the one that takes typing.
    await tester.tap(find.text('喝水'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '喝了 8 杯');
    await tester.tap(
      find.descendant(
        of: find.byType(HabitCheckInSheet),
        matching: find.text(AppStrings.habitCheckIn),
      ),
    );
    await tester.pumpAndSettle();

    final List<HabitLog> logs = await repository.loadLogs();
    expect(logs.single.note, '喝了 8 杯');
  });

  testWidgets('a habit that forbids notes is checked off in one tap only', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeHabitRepository repository = FakeHabitRepository(
      habits: <Habit>[habit('h1', name: '吃药', allowNote: false)],
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    await tester.tap(find.text('吃药'));
    await tester.pumpAndSettle();

    // No field to type into, and saving still records the check-in.
    expect(find.byType(TextField), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(HabitCheckInSheet),
        matching: find.text(AppStrings.habitCheckIn),
      ),
    );
    await tester.pumpAndSettle();
    expect((await repository.loadLogs()).single.note, isNull);
  });

  testWidgets('deleting a habit takes its records with it', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    final FakeHabitRepository repository = FakeHabitRepository(
      habits: <Habit>[habit('h1', name: '吃药')],
      logs: <HabitLog>[
        HabitLog(habitId: 'h1', dayKey: habitDayKey(testNow), at: testNow),
      ],
    );
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.habitEdit));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.actionDelete));
    await tester.pumpAndSettle();

    // The confirmation says what is at stake, because the records go too.
    expect(find.text(AppStrings.habitDeleteTitle), findsOneWidget);
    await tester.tap(find.text(AppStrings.confirm));
    await tester.pumpAndSettle();

    expect(await repository.loadHabits(), isEmpty);
    expect(await repository.loadLogs(), isEmpty);
    expect(find.text(AppStrings.habitEmptyTitle), findsOneWidget);
  });

  testWidgets('the record sheet lists what was written', (
    WidgetTester tester,
  ) async {
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: FakeHabitRepository(
          habits: <Habit>[habit('h1', name: '喝水')],
          logs: <HabitLog>[
            HabitLog(
              habitId: 'h1',
              dayKey: habitDayKey(testNow),
              at: testNow,
              note: '喝了 8 杯',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.habitHistory));
    await tester.pumpAndSettle();

    expect(find.text('喝了 8 杯'), findsOneWidget);
  });

  testWidgets('the widget section is only offered where there is a home screen', (
    WidgetTester tester,
  ) async {
    // Widget tests run off Android, so the honest behaviour to pin down is that
    // the offer is absent rather than present and useless.
    _usePhoneWindow(tester);
    await tester.pumpWidget(
      buildTestApp(
        repository: FakeTodoRepository(),
        habitRepository: FakeHabitRepository(habits: <Habit>[habit('h1')]),
      ),
    );
    await tester.pumpAndSettle();
    await openHabits(tester);

    expect(find.text(AppStrings.habitWidgetSection), findsNothing);
    expect(find.text(AppStrings.habitWidgetAdd), findsNothing);
  });
}

/// A phone-sized window: the habits page is a list, and a short window is what
/// makes its rows and the sheets that open over them behave as they will on a
/// real device.
void _usePhoneWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
