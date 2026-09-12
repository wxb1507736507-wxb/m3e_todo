import 'package:flutter/widgets.dart';

/// The Material 3 Expressive shape scale.
///
/// Expressive surfaces are noticeably rounder than baseline Material 3, and the
/// scale gained intermediate steps (`largeIncreased`, `extraLargeIncreased`) so
/// nested surfaces can step their corners without jumping a whole size.
abstract final class AppShapes {
  /// Square. Used for full-bleed surfaces that meet a screen edge.
  static const double none = 0;

  /// Menus, small inputs, checkboxes.
  static const double extraSmall = 4;

  /// Chips, small buttons.
  static const double small = 8;

  /// Cards in dense layouts, snackbars.
  static const double medium = 12;

  /// Default card and container radius.
  static const double large = 16;

  /// Nested container sitting inside a [large] surface.
  static const double largeIncreased = 20;

  /// Dialogs, bottom sheets, navigation rail indicator &mdash; the signature
  /// Expressive radius.
  static const double extraLarge = 28;

  /// A card nested inside an [extraLarge] surface.
  static const double extraLargeIncreased = 32;

  /// Large feature surfaces such as hero panels.
  static const double extraExtraLarge = 48;

  /// Fully rounded. Clamped because [BorderRadius] validates its input.
  static const double full = 999;

  static const BorderRadius noneRadius = BorderRadius.zero;

  /// A circular border radius of [value].
  static BorderRadius radius(double value) => BorderRadius.circular(value);

  /// An [OutlinedBorder] with circular corners of [value].
  static RoundedRectangleBorder border(double value) {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(value));
  }

  /// The classic Expressive pill shape used by buttons, chips and search bars.
  static const RoundedRectangleBorder pill = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(full)),
  );

  /// A stadium (fully rounded, non-circular) border.
  static const StadiumBorder stadium = StadiumBorder();
}
