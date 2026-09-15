import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_strings.dart';
import '../core/theme/app_color_schemes.dart';
import '../core/theme/app_theme.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/settings_controller.dart';
import '../features/timetable/presentation/pages/timetable_page.dart';
import 'app_shell.dart';

/// The root widget.
///
/// Themes are rebuilt here from the current settings rather than being cached in
/// a provider, because [AppColorSchemes] already memoises the expensive part
/// (the tonal-palette generation), leaving only cheap [ThemeData] assembly.
class M3eTodoApp extends ConsumerWidget {
  const M3eTodoApp({this.opensOnTimetable = false, super.key});

  /// Whether the app was opened *by a course tile*, in which case the timetable
  /// is the first thing on screen and the shell waits underneath it.
  final bool opensOnTimetable;

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
      // Named routes rather than a hand-written initial-route generator: asking
      // for `/timetable` makes Flutter build the whole stack — the shell first,
      // then the timetable — so a tile's tap lands on the timetable with no
      // flash of the list underneath, and going back reaches the app.
      initialRoute: opensOnTimetable ? _timetableRoute : _shellRoute,
      routes: <String, WidgetBuilder>{
        _shellRoute: (_) => const AppShell(),
        _timetableRoute: (_) => const TimetablePage(),
      },
    );
  }
}

/// The app's own screen, and the one a course tile asks for.
const String _shellRoute = '/';
const String _timetableRoute = '/timetable';
