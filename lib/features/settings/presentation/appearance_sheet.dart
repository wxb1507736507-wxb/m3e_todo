import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_color_schemes.dart';
import '../../../core/theme/app_motion.dart';
import '../domain/app_settings.dart';
import 'settings_controller.dart';

/// Opens the appearance sheet.
Future<void> showAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (BuildContext context) => const AppearanceSheet(),
  );
}

/// Lets the user pick light/dark/system and the seed colour.
///
/// Both controls write straight through to [SettingsController], which applies
/// the change immediately: the sheet is the preview, so the user sees the result
/// on the whole app before dismissing it.
class AppearanceSheet extends ConsumerWidget {
  const AppearanceSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(AppStrings.appearanceTitle, style: text.headlineSmall),
          const SizedBox(height: 24),
          Text(AppStrings.themeModeLabel, style: text.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<AppThemeMode>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<AppThemeMode>>[
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.system,
                label: Text(AppStrings.themeSystem),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.light,
                label: Text(AppStrings.themeLight),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment<AppThemeMode>(
                value: AppThemeMode.dark,
                label: Text(AppStrings.themeDark),
                icon: Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: <AppThemeMode>{settings.themeMode},
            onSelectionChanged: (Set<AppThemeMode> selection) =>
                controller.setThemeMode(selection.first),
          ),
          const SizedBox(height: 28),
          Text(AppStrings.colorSeedLabel, style: text.labelLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 16,
            children: <Widget>[
              for (final AppColorSeed seed in AppColorSeed.values)
                _SeedSwatch(
                  seed: seed,
                  label: _seedLabel(seed),
                  selected: seed == settings.colorSeed,
                  onTap: () => controller.setColorSeed(seed),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _seedLabel(AppColorSeed seed) {
    return switch (seed) {
      AppColorSeed.violet => AppStrings.colorSeedViolet,
      AppColorSeed.ocean => AppStrings.colorSeedOcean,
      AppColorSeed.teal => AppStrings.colorSeedTeal,
      AppColorSeed.forest => AppStrings.colorSeedForest,
      AppColorSeed.amber => AppStrings.colorSeedAmber,
      AppColorSeed.rose => AppStrings.colorSeedRose,
    };
  }
}

/// A colour choice, shown as the *generated* primary colour rather than the raw
/// seed.
///
/// The expressive variant deliberately moves the hue away from the seed, so
/// previewing the seed directly would promise a colour the app never actually
/// uses.
class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.seed,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppColorSeed seed;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme preview = AppColorSchemes.light(seed);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: AppMotion.effectsFast.duration,
                curve: AppMotion.effectsFast.curve,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: preview.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? colors.onSurface : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, color: preview.onPrimary, size: 24)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(label, style: text.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
