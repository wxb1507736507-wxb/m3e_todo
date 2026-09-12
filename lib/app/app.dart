import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_strings.dart';
import '../core/theme/app_color_schemes.dart';
import '../core/theme/app_theme.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/settings_controller.dart';
import 'app_shell.dart';

/// The root widget.
///
/// Themes are rebuilt here from the current settings rather than being cached in
/// a provider, because [AppColorSchemes] already memoises the expensive part
/// (the tonal-palette generation), leaving only cheap [ThemeData] assembly.
class M3eTodoApp extends ConsumerWidget {
  const M3eTodoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.colorSeed),
      darkTheme: AppTheme.dark(settings.colorSeed),
      themeMode: AppColorSchemes.themeModeOf(settings.themeMode),
      home: const AppShell(),
    );
  }
}
