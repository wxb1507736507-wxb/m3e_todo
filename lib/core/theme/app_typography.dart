import 'package:flutter/material.dart';

/// Material 3 Expressive type adjustments.
///
/// Baseline Material 3 keeps the whole scale at regular weight. Expressive adds
/// *emphasis*: the display, headline and title roles step up to medium/semi-bold
/// with tightened tracking, while body and label roles stay regular so long-form
/// text remains comfortable. That contrast is what makes an Expressive screen
/// feel typographically anchored.
///
/// Only weights and letter spacing are touched. Sizes come from the platform
/// typography (`Typography.material2021`) so text scaling and localisation keep
/// working.
abstract final class AppTypography {
  /// Returns [base] with the Expressive emphasis weights applied.
  static TextTheme apply(TextTheme base) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: -0.25,
      ),
      displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w500),
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
      ),
      headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}
