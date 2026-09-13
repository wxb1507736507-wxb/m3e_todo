import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/features/settings/presentation/appearance_sheet.dart';

import '../../../support/fake_todo_repository.dart';
import '../../../support/test_app.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    // The sheet persists every change, so it needs somewhere real to write.
    // Tests never touch the developer's actual data directory, because
    // buildTestApp redirects storage to a throwaway directory by default.
    tempDir = Directory.systemTemp.createTempSync('m3e_todo_appearance');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// The app-level [MaterialApp], read directly rather than through
  /// `Theme.of`, because `Theme.of` on the MaterialApp's own element resolves
  /// to the *parent* theme, not the one the app just built.
  MaterialApp appOf(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestApp(repository: FakeTodoRepository(), dataDirectory: tempDir),
    );
    await tester.pumpAndSettle();
    // Appearance no longer has its own app-bar button: the app bar now opens
    // the integrated settings sheet, and the appearance controls live in its
    // second section.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  /// Scrolls [finder] into the sheet's viewport before tapping it. The sheet is
  /// taller than the test window, so the lower controls start off-screen and a
  /// bare `tap` would miss them.
  Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('the settings entry point shows the appearance controls', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);

    expect(find.byType(AppearanceSheet), findsOneWidget);
    expect(find.text(AppStrings.appearanceTitle), findsOneWidget);
  });

  testWidgets('picking dark mode applies it to the whole app', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);
    expect(appOf(tester).themeMode, ThemeMode.system);

    await tapInSheet(tester, find.text(AppStrings.themeDark));

    expect(appOf(tester).themeMode, ThemeMode.dark);
  });

  testWidgets('picking a seed colour regenerates the palette', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);
    final Color before = appOf(tester).theme!.colorScheme.primary;

    await tapInSheet(tester, find.text(AppStrings.colorSeedRose));

    expect(appOf(tester).theme!.colorScheme.primary, isNot(before));
  });

  // Persistence is covered by settings_controller_test.dart instead. Writing to
  // disk from inside `testWidgets` does not work: the widget test body runs in a
  // zone with faked timers, so a dart:io completion started there is never
  // delivered and awaiting it hangs the test.
}
