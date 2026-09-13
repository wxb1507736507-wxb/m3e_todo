import 'package:flutter/material.dart';

import '../../features/settings/domain/app_settings.dart';
import 'app_color_schemes.dart';
import 'app_component_themes.dart';
import 'app_page_transitions.dart';
import 'app_typography.dart';

/// Assembles the Material 3 Expressive [ThemeData] for the app.
///
/// A single [ThemeData] is built per brightness and then handed to
/// [MaterialApp], so `Theme.of(context)` returns a fully-resolved theme and no
/// widget needs to hard-code a colour. Every value here derives from the
/// generated [ColorScheme], which means changing the seed recolours the entire
/// app without touching another file.
abstract final class AppTheme {
  static ThemeData light(AppColorSeed seed, {bool translucent = false}) {
    return _build(AppColorSchemes.light(seed), translucent: translucent);
  }

  static ThemeData dark(AppColorSeed seed, {bool translucent = false}) {
    return _build(AppColorSchemes.dark(seed), translucent: translucent);
  }

  /// How much of the surface colour survives in the chrome when a background
  /// image is behind the app.
  ///
  /// Not fully transparent: the app bar and navigation bar carry text and icons,
  /// and letting a busy photo through at full strength would make both
  /// unreadable. 0.86 keeps them clearly a surface while the photo still reads
  /// through.
  static const double _chromeOpacity = 0.86;

  static ThemeData _build(ColorScheme colors, {bool translucent = false}) {
    // Starting from ThemeData(colorScheme: ...) keeps every Material 3 default
    // the framework computes, so this only layers the Expressive adjustments on
    // top instead of re-deriving the whole theme.
    final ThemeData base = ThemeData(colorScheme: colors);
    final TextTheme text = AppTypography.apply(base.textTheme);
    final Color chrome = colors.surface.withValues(alpha: _chromeOpacity);

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: AppTypography.apply(base.primaryTextTheme),
      // With a background image the scaffold must not paint over it; the bars
      // become translucent so the photo continues behind them.
      scaffoldBackgroundColor: translucent ? Colors.transparent : colors.surface,
      canvasColor: colors.surface,
      // Material 3 Expressive is tuned for generous targets. Flutter's desktop
      // default is `compact`, which would shrink every control below the
      // comfortable size the design language assumes.
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: AppPageTransitions.theme,
      appBarTheme: translucent
          ? AppComponentThemes.appBar(colors, text).copyWith(backgroundColor: chrome)
          : AppComponentThemes.appBar(colors, text),
      cardTheme: AppComponentThemes.card(colors),
      dialogTheme: AppComponentThemes.dialog(colors),
      bottomSheetTheme: AppComponentThemes.bottomSheet(colors),
      snackBarTheme: AppComponentThemes.snackBar(colors, text),
      inputDecorationTheme: AppComponentThemes.inputDecoration(colors, text),
      segmentedButtonTheme: AppComponentThemes.segmentedButton(colors, text),
      filledButtonTheme: AppComponentThemes.filledButton(text),
      outlinedButtonTheme: AppComponentThemes.outlinedButton(colors, text),
      textButtonTheme: AppComponentThemes.textButton(text),
      elevatedButtonTheme: AppComponentThemes.elevatedButton(text),
      iconButtonTheme: AppComponentThemes.iconButton(),
      floatingActionButtonTheme: AppComponentThemes.floatingActionButton(
        colors,
        text,
      ),
      checkboxTheme: AppComponentThemes.checkbox(colors),
      chipTheme: AppComponentThemes.chip(),
      listTileTheme: AppComponentThemes.listTile(colors, text),
      navigationRailTheme: translucent
          ? AppComponentThemes.navigationRail(colors, text)
              .copyWith(backgroundColor: chrome)
          : AppComponentThemes.navigationRail(colors, text),
      navigationBarTheme: translucent
          ? AppComponentThemes.navigationBar(colors, text)
              .copyWith(backgroundColor: chrome)
          : AppComponentThemes.navigationBar(colors, text),
      dividerTheme: AppComponentThemes.divider(colors),
      scrollbarTheme: AppComponentThemes.scrollbar(colors),
      tooltipTheme: AppComponentThemes.tooltip(colors, text),
      menuTheme: AppComponentThemes.menu(colors),
      progressIndicatorTheme: AppComponentThemes.progressIndicator(colors),
      badgeTheme: AppComponentThemes.badge(colors, text),
    );
  }
}
