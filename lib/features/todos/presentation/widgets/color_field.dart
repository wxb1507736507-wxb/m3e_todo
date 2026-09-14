import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../media/presentation/color_picker_page.dart';

/// One "choose a colour" row: presets, a free picker, a sampler, and a
/// follow-the-theme option.
///
/// Shared by the tile colour and the text colour on purpose. They are the same
/// decision made twice, and the two rows must not drift apart — a preset that
/// appears for one and not the other would be a bug nobody notices until they
/// want it.
class ColorField extends StatelessWidget {
  const ColorField({
    required this.label,
    required this.value,
    required this.noneLabel,
    required this.presets,
    required this.onChanged,
    this.onSample,
    this.warning,
    super.key,
  });

  /// What this colour is, e.g. 「色块颜色」.
  final String label;

  /// Current ARGB32 value, or `null` for "follow the theme".
  final int? value;

  /// Label for the `null` choice — 「跟随主题」 for a tile, 「自动」 for text.
  final String noneLabel;

  final List<AppPaletteColor> presets;
  final ValueChanged<int?> onChanged;

  /// Samples a colour from a picture; `null` hides the affordance.
  ///
  /// A callback rather than a path because *where* the picture comes from is
  /// context the field should not know: the editor prefers the todo's own
  /// background image and falls back to asking the user for one.
  final Future<int?> Function()? onSample;

  /// Message shown under the row when the choice is hard to read.
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final int? current = value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label, style: text.labelLarge)),
            // The follow-the-theme choice plus whatever the user has currently
            // set, so the row states its own value instead of relying on a ring
            // somewhere in the swatch grid.
            _Choice(
              label: noneLabel,
              selected: current == null,
              onTap: () => onChanged(null),
            ),
            if (current != null) ...<Widget>[
              const SizedBox(width: 8),
              _Choice(
                label: hexFromArgb(current),
                selected: true,
                color: Color(current),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            for (final AppPaletteColor preset in presets)
              _Swatch(
                argb: preset.argb,
                label: preset.label,
                selected: current == preset.argb,
                onTap: () => onChanged(preset.argb),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () => unawaited(_pickCustom(context)),
              icon: const Icon(Icons.palette_outlined),
              label: const Text(AppStrings.colorCustom),
            ),
            if (onSample != null)
              OutlinedButton.icon(
                onPressed: () => unawaited(_sample(context)),
                icon: const Icon(Icons.colorize),
                label: const Text(AppStrings.colorPick),
              ),
          ],
        ),
        if (warning != null) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, size: 16, color: colors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning!,
                  style: text.bodySmall?.copyWith(color: colors.error),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final int? picked = await pickCustomColor(context, initial: value);
    if (picked != null) {
      onChanged(picked);
    }
  }

  Future<void> _sample(BuildContext context) async {
    final int? picked = await onSample!.call();
    if (picked != null) {
      onChanged(picked);
    }
  }
}

/// A small pill showing one of the two "special" choices (follow the theme, or
/// the current custom value).
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    this.color,
    this.onTap,
  });

  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : colors.surfaceContainerHighest,
          borderRadius: AppRadius.pill,
          border: Border.all(
            color: selected ? colors.secondary : colors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (color != null) ...<Widget>[
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.outlineVariant),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: text.labelMedium?.copyWith(
                color: selected ? colors.onSecondaryContainer : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A named preset colour.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.argb,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int argb;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(argb),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check, size: 18, color: Color(readableOn(argb)))
                : null,
          ),
        ),
      ),
    );
  }
}

/// Pill radius shared by the small choice chips.
abstract final class AppRadius {
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}
