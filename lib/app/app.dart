import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
      // AppStrings covers this app's own text, but the *platform* surfaces —
      // most visibly the date picker behind every due date — are drawn by
      // Material itself. Without these delegates they fall back to English
      // inside an otherwise Chinese UI.
      locale: const Locale('zh'),
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(
        settings.colorSeed,
        translucent: settings.hasBackground,
      ),
      darkTheme: AppTheme.dark(
        settings.colorSeed,
        translucent: settings.hasBackground,
      ),
      themeMode: AppColorSchemes.themeModeOf(settings.themeMode),
      home: const AppShell(),
    );
  }
}
