import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/theme/app_color_schemes.dart';
import 'package:m3e_todo/core/theme/app_page_transitions.dart';
import 'package:m3e_todo/core/theme/app_shapes.dart';
import 'package:m3e_todo/core/theme/app_theme.dart';
import 'package:m3e_todo/features/settings/domain/app_settings.dart';

void main() {
  test('builds a light and a dark theme for every seed', () {
    for (final AppColorSeed seed in AppColorSeed.values) {
      expect(AppTheme.light(seed).colorScheme.brightness, Brightness.light);
      expect(AppTheme.dark(seed).colorScheme.brightness, Brightness.dark);
    }
  });

  test('generates colour with the Expressive variant, not the default', () {
    final ColorScheme light = AppColorSchemes.light(AppColorSeed.violet);
    final ColorScheme tonalSpot = ColorScheme.fromSeed(
      seedColor: AppColorSchemes.seedOf(AppColorSeed.violet),
    );

    // SchemeExpressive rotates the primary palette's hue by 240 degrees relative
    // to the seed, whereas the default tonalSpot uses the seed hue unchanged.
    // If someone drops the variant, this is what catches it.
    expect(light.primary, isNot(tonalSpot.primary));
    expect(light.tertiary, isNot(tonalSpot.tertiary));
  });

  test('memoises generated schemes so rebuilds stay cheap', () {
    expect(
      identical(
        AppColorSchemes.light(AppColorSeed.teal),
        AppColorSchemes.light(AppColorSeed.teal),
      ),
      isTrue,
    );
    expect(
      identical(
        AppColorSchemes.light(AppColorSeed.teal),
        AppColorSchemes.dark(AppColorSeed.teal),
      ),
      isFalse,
    );
  });

  group('theme assembly', () {
    final ThemeData theme = AppTheme.light(AppColorSeed.violet);

    test('applies the Expressive emphasis weights to titles', () {
      expect(theme.textTheme.titleLarge?.fontWeight, FontWeight.w700);
      expect(theme.textTheme.headlineSmall?.fontWeight, FontWeight.w600);
    });

    test('uses the Expressive shape scale for cards and dialogs', () {
      expect(
        (theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(AppShapes.large),
      );
      expect(
        (theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(AppShapes.extraLarge),
      );
    });

    test('makes buttons pills', () {
      final OutlinedBorder? shape =
          theme.filledButtonTheme.style?.shape?.resolve(<WidgetState>{});
      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape! as RoundedRectangleBorder).borderRadius,
        const BorderRadius.all(Radius.circular(AppShapes.full)),
      );
    });

    test('keeps controls at the comfortable size the design language assumes',
        () {
      // Flutter's desktop default is `compact`, which would shrink every
      // control below the Expressive target size.
      expect(theme.visualDensity, VisualDensity.standard);
    });

    test('paints the scaffold with the scheme surface colour', () {
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
    });

    test('registers the Expressive page transition for Windows', () {
      expect(
        theme.pageTransitionsTheme.builders[TargetPlatform.windows],
        isA<ExpressivePageTransitionsBuilder>(),
      );
    });
  });

  test('maps every settings theme mode onto a Flutter ThemeMode', () {
    expect(AppColorSchemes.themeModeOf(AppThemeMode.system), ThemeMode.system);
    expect(AppColorSchemes.themeModeOf(AppThemeMode.light), ThemeMode.light);
    expect(AppColorSchemes.themeModeOf(AppThemeMode.dark), ThemeMode.dark);
  });

  test('building every palette is idempotent — the second pass is free', () {
    AppColorSchemes.buildAll();
    // Identity, not equality: this is what makes a theme rebuild cheap, and it
    // is the one property the (removed) warm-up loop depended on.
    for (final AppColorSeed seed in AppColorSeed.values) {
      expect(
        identical(AppColorSchemes.light(seed), AppColorSchemes.light(seed)),
        isTrue,
      );
      expect(
        identical(AppColorSchemes.dark(seed), AppColorSchemes.dark(seed)),
        isTrue,
      );
    }
  });

  group('translucent chrome (application background)', () {
    // With a background image the scaffold must let the image through, and the
    // bars must stay *translucent but not transparent*: the app bar carries the
    // title and the navigation bar carries labels, and neither is readable over
    // an arbitrary photo at full strength.
    final ThemeData theme = AppTheme.light(AppColorSeed.violet, translucent: true);

    test('lets the scaffold show the background through', () {
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
    });

    test('keeps the app bar and navigation bars translucent', () {
      final Color bar = theme.appBarTheme.backgroundColor!;
      expect(bar.a, greaterThan(0.5));
      expect(bar.a, lessThan(1.0));

      final Color rail = theme.navigationRailTheme.backgroundColor!;
      expect(rail.a, lessThan(1.0));
      final Color navBar = theme.navigationBarTheme.backgroundColor!;
      expect(navBar.a, lessThan(1.0));
    });

    test('leaves menus and dialogs opaque', () {
      // Only the chrome gets out of the way; anything that floats above the app
      // keeps a solid surface so its content stays readable.
      expect(theme.canvasColor, theme.colorScheme.surface);
      expect(theme.dialogTheme.backgroundColor?.a, 1.0);
      expect(theme.bottomSheetTheme.backgroundColor?.a, 1.0);
    });

    test('an opaque theme is unchanged by the new parameter', () {
      final ThemeData plain = AppTheme.light(AppColorSeed.violet);
      expect(plain.scaffoldBackgroundColor, plain.colorScheme.surface);
      expect(plain.appBarTheme.backgroundColor?.a, 1.0);
    });
  });
}
