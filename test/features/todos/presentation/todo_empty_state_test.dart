import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/constants/app_strings.dart';
import 'package:m3e_todo/core/theme/app_theme.dart';
import 'package:m3e_todo/features/settings/domain/app_settings.dart';
import 'package:m3e_todo/features/todos/presentation/widgets/todo_empty_state.dart';

/// Regression tests for the empty state's layout.
///
/// The dimensions below are not invented: 248 x 141 is exactly what the widget
/// received on a Pixel-class phone (360 x 790 logical, 720 x 1580 physical) with
/// the on-screen keyboard open, as reported by Flutter's own overflow error.
/// Before the widget was made scrollable it overflowed by 43 pixels there,
/// painting the yellow-and-black stripes across the placeholder. Desktop and web
/// never shrank that far, so nothing caught it until the app ran on a real
/// device.
///
/// Kept as separate `const double`s rather than a `Size`, because a constant's
/// getter is not itself a constant expression and so cannot be used inside a
/// `const` widget.
const double _phoneContentWidth = 248;
const double _phoneContentHeight = 141;

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(AppColorSeed.violet),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('fits the phone-with-keyboard constraints that used to overflow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Center(
          child: SizedBox(
            width: _phoneContentWidth,
            height: _phoneContentHeight,
            child: TodoEmptyState(
              icon: Icons.playlist_add,
              title: AppStrings.emptyAllTitle,
              body: AppStrings.emptyAllBody,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The message itself must survive; only the decoration may be dropped.
    expect(find.text(AppStrings.emptyAllTitle), findsOneWidget);
  });

  testWidgets('drops the decorative icon when there is no room for it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Center(
          child: SizedBox(
            width: _phoneContentWidth,
            height: _phoneContentHeight,
            child: TodoEmptyState(
              icon: Icons.playlist_add,
              title: AppStrings.emptyAllTitle,
              body: AppStrings.emptyAllBody,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.playlist_add), findsNothing);
  });

  testWidgets('keeps the icon when there is room', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const TodoEmptyState(
          icon: Icons.playlist_add,
          title: AppStrings.emptyAllTitle,
          body: AppStrings.emptyAllBody,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.playlist_add), findsOneWidget);
  });

  testWidgets('handles an extremely short viewport without overflowing', (
    WidgetTester tester,
  ) async {
    // Smaller than anything real, to prove the widget degrades by scrolling
    // rather than only working above some threshold just below the reported size.
    await tester.pumpWidget(
      _host(
        const Center(
          child: SizedBox(
            width: 200,
            height: 60,
            child: TodoEmptyState(
              icon: Icons.search_off,
              title: AppStrings.emptySearchTitle,
              body: AppStrings.emptySearchBody,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
