import 'package:flutter/material.dart';

import 'app_shapes.dart';

/// Per-component Material theme overrides.
///
/// [ThemeData] already derives sound Material 3 defaults from the
/// [ColorScheme], so this file only touches the places where the Expressive
/// conventions differ: rounder shapes, flatter surfaces (no elevation tint),
/// pill controls and roomier padding. Keeping the diff small makes the theme
/// easy to review and to re-tune later.
abstract final class AppComponentThemes {
  /// Minimum height for interactive controls.
  ///
  /// Expressive targets are generous, and 48 logical pixels also satisfies the
  /// Windows accessibility guidance for pointer targets.
  static const double controlHeight = 48;

  static AppBarThemeData appBar(ColorScheme colors, TextTheme text) {
    return AppBarThemeData(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    );
  }

  static CardThemeData card(ColorScheme colors) {
    return CardThemeData(
      color: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: AppShapes.border(AppShapes.large),
    );
  }

  static DialogThemeData dialog(ColorScheme colors) {
    return DialogThemeData(
      backgroundColor: colors.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: AppShapes.border(AppShapes.extraLarge),
    );
  }

  static BottomSheetThemeData bottomSheet(ColorScheme colors) {
    return BottomSheetThemeData(
      backgroundColor: colors.surfaceContainerLow,
      modalBackgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: colors.onSurfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppShapes.extraLarge),
        ),
      ),
    );
  }

  static SnackBarThemeData snackBar(ColorScheme colors, TextTheme text) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: colors.onInverseSurface,
      ),
      actionTextColor: colors.inversePrimary,
      closeIconColor: colors.onInverseSurface,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      shape: AppShapes.border(AppShapes.medium),
      showCloseIcon: true,
    );
  }

  static InputDecorationThemeData inputDecoration(
    ColorScheme colors,
    TextTheme text,
  ) {
    final OutlineInputBorder base = OutlineInputBorder(
      borderRadius: AppShapes.radius(AppShapes.extraLarge),
      borderSide: BorderSide.none,
    );

    return InputDecorationThemeData(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      hintStyle: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
      labelStyle: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
      helperStyle: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      errorStyle: text.bodySmall?.copyWith(color: colors.error),
      border: base,
      enabledBorder: base,
      disabledBorder: base,
      focusedBorder: base.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      errorBorder: base.copyWith(
        borderSide: BorderSide(color: colors.error, width: 2),
      ),
      focusedErrorBorder: base.copyWith(
        borderSide: BorderSide(color: colors.error, width: 2),
      ),
      prefixIconColor: colors.onSurfaceVariant,
      suffixIconColor: colors.onSurfaceVariant,
    );
  }

  static SegmentedButtonThemeData segmentedButton(
    ColorScheme colors,
    TextTheme text,
  ) {
    // Shape is left at the Material default: SegmentedButton computes the
    // per-segment corner rounding itself, and overriding it would square off the
    // group's rounded ends.
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: colors.outline),
        ),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.secondaryContainer
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }

  static FilledButtonThemeData filledButton(TextTheme text) {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, controlHeight),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: AppShapes.pill,
        textStyle: text.labelLarge,
        elevation: 0,
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButton(
    ColorScheme colors,
    TextTheme text,
  ) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, controlHeight),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: AppShapes.pill,
        textStyle: text.labelLarge,
        side: BorderSide(color: colors.outline),
      ),
    );
  }

  static TextButtonThemeData textButton(TextTheme text) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: AppShapes.pill,
        textStyle: text.labelLarge,
      ),
    );
  }

  static ElevatedButtonThemeData elevatedButton(TextTheme text) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(64, controlHeight),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: AppShapes.pill,
        textStyle: text.labelLarge,
        elevation: 0,
      ),
    );
  }

  static IconButtonThemeData iconButton() {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: AppShapes.stadium,
        iconSize: 22,
      ),
    );
  }

  static FloatingActionButtonThemeData floatingActionButton(
    ColorScheme colors,
    TextTheme text,
  ) {
    return FloatingActionButtonThemeData(
      backgroundColor: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: AppShapes.border(AppShapes.large),
      extendedTextStyle: text.labelLarge,
    );
  }

  static CheckboxThemeData checkbox(ColorScheme colors) {
    return CheckboxThemeData(
      shape: AppShapes.border(AppShapes.extraSmall),
      side: BorderSide(color: colors.outline, width: 2),
      fillColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? colors.primary
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll<Color>(colors.onPrimary),
      visualDensity: VisualDensity.standard,
    );
  }

  /// Colours are intentionally omitted so the framework's own selected-state
  /// label colours keep working; only the Expressive shape and padding differ.
  static ChipThemeData chip() {
    return const ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppShapes.small)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      showCheckmark: true,
    );
  }

  static ListTileThemeData listTile(ColorScheme colors, TextTheme text) {
    return ListTileThemeData(
      shape: AppShapes.border(AppShapes.large),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      minVerticalPadding: 12,
      horizontalTitleGap: 16,
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
      ),
      iconColor: colors.onSurfaceVariant,
    );
  }

  static NavigationRailThemeData navigationRail(
    ColorScheme colors,
    TextTheme text,
  ) {
    return NavigationRailThemeData(
      backgroundColor: colors.surface,
      elevation: 0,
      indicatorColor: colors.secondaryContainer,
      indicatorShape: AppShapes.stadium,
      selectedIconTheme: IconThemeData(
        color: colors.onSecondaryContainer,
        size: 24,
      ),
      unselectedIconTheme: IconThemeData(
        color: colors.onSurfaceVariant,
        size: 24,
      ),
      selectedLabelTextStyle: text.labelMedium?.copyWith(
        color: colors.onSurface,
      ),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(
        color: colors.onSurfaceVariant,
      ),
    );
  }

  static NavigationBarThemeData navigationBar(
    ColorScheme colors,
    TextTheme text,
  ) {
    return NavigationBarThemeData(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: colors.secondaryContainer,
      indicatorShape: AppShapes.stadium,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
        (Set<WidgetState> states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
          size: 24,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
        (Set<WidgetState> states) => text.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }

  static DividerThemeData divider(ColorScheme colors) {
    return DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    );
  }

  static ScrollbarThemeData scrollbar(ColorScheme colors) {
    return ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll<double>(8),
      radius: const Radius.circular(AppShapes.extraSmall),
      thumbColor: WidgetStatePropertyAll<Color>(
        colors.onSurfaceVariant.withValues(alpha: 0.4),
      ),
      trackColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      crossAxisMargin: 4,
    );
  }

  static TooltipThemeData tooltip(ColorScheme colors, TextTheme text) {
    return TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      showDuration: const Duration(seconds: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: AppShapes.radius(AppShapes.small),
      ),
      textStyle: text.bodySmall?.copyWith(color: colors.onInverseSurface),
    );
  }

  static MenuThemeData menu(ColorScheme colors) {
    return MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color?>(
          colors.surfaceContainer,
        ),
        surfaceTintColor: const WidgetStatePropertyAll<Color?>(
          Colors.transparent,
        ),
        shadowColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
        elevation: const WidgetStatePropertyAll<double?>(0),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry?>(
          EdgeInsets.symmetric(vertical: 8),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder?>(
          AppShapes.border(AppShapes.medium),
        ),
      ),
    );
  }

  static ProgressIndicatorThemeData progressIndicator(ColorScheme colors) {
    return ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.surfaceContainerHighest,
      linearMinHeight: 6,
    );
  }

  /// Badges are used here to show *counts*, not errors, so they take the primary
  /// colour. The Material default (error red) would make an ordinary "3 active
  /// todos" look like a warning.
  static BadgeThemeData badge(ColorScheme colors, TextTheme text) {
    return BadgeThemeData(
      backgroundColor: colors.primary,
      textColor: colors.onPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      textStyle: text.labelSmall,
    );
  }
}
