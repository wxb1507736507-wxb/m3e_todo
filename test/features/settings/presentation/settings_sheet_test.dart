import 'package:m3e_todo/features/notifications/domain/reminder.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/settings/presentation/appearance_sheet.dart';
import 'package:m3e_todo/features/settings/presentation/settings_sheet.dart';

import '../../../support/fake_todo_repository.dart';
import '../../../support/test_app.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('m3e_todo_settings');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestApp(repository: FakeTodoRepository(), dataDirectory: tempDir),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('the app bar opens one sheet holding every section', (
    WidgetTester tester,
  ) async {
    await openSettings(tester);

    expect(find.byType(SettingsSheet), findsOneWidget);
    expect(find.text(AppStrings.settingsTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsSectionReminders), findsOneWidget);
    expect(find.text(AppStrings.settingsSectionAppearance), findsOneWidget);
    expect(find.text(AppStrings.settingsSectionTips), findsOneWidget);
    // Appearance is embedded rather than reachable only through its own sheet.
    expect(find.byType(AppearanceSheet), findsOneWidget);
  });

  testWidgets('the tips section explains the new features', (
    WidgetTester tester,
  ) async {
    await openSettings(tester);

    for (final String tip in <String>[
      AppStrings.tipReorder,
      AppStrings.tipSubtask,
      AppStrings.tipCalendar,
      AppStrings.tipAttachment,
      AppStrings.tipAppearance,
      AppStrings.tipAppBackground,
    ]) {
      expect(find.text(tip), findsOneWidget, reason: tip);
    }
  });

  testWidgets('the application background section offers to pick an image', (
    WidgetTester tester,
  ) async {
    await openSettings(tester);

    expect(find.text(AppStrings.settingsSectionBackground), findsOneWidget);
    // One picker for the app and one for the home-screen tiles, which are two
    // different pictures on purpose: a tile is seen through a launcher's own
    // chrome, a few centimetres from the app's own screens.
    expect(find.text(AppStrings.appBackgroundPick), findsNWidgets(2));
    expect(find.text(AppStrings.widgetBackgroundLabel), findsOneWidget);
    // With no image chosen there is nothing to crop, remove or dim yet — the
    // controls appear only once there is.
    expect(find.text(AppStrings.appBackgroundNone), findsNWidgets(2));
    expect(find.text(AppStrings.cropBackgroundImage), findsNothing);
    expect(find.text(AppStrings.appBackgroundRemove), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('switching the reminder to silent reaches the settings state', (
    WidgetTester tester,
  ) async {
    await openSettings(tester);

    expect(
      tester
          .widget<SegmentedButton<ReminderMode>>(
            find.byType(SegmentedButton<ReminderMode>),
          )
          .selected,
      <ReminderMode>{ReminderMode.ring},
    );

    await tester.ensureVisible(find.text(AppStrings.reminderModeSilent));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.reminderModeSilent));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SegmentedButton<ReminderMode>>(
            find.byType(SegmentedButton<ReminderMode>),
          )
          .selected,
      <ReminderMode>{ReminderMode.silent},
    );
  });

  // The ringtone picker, the permission prompt and the test notification are
  // all Android-only, and widget tests run on the host: the controls must be
  // absent rather than present-but-dead.
  testWidgets('Android-only controls stay hidden off Android', (
    WidgetTester tester,
  ) async {
    await openSettings(tester);

    expect(find.text(AppStrings.ringtoneLabel), findsNothing);
    expect(find.text(AppStrings.notificationTest), findsNothing);
    expect(find.text(AppStrings.notificationPermissionNeeded), findsNothing);
  });
}
