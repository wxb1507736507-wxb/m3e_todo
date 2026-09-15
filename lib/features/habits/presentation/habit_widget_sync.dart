import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/platform/app_platform.dart';
import '../../notifications/domain/reminder.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/presentation/settings_controller.dart';
import '../domain/entities/habit.dart';
import '../domain/entities/habit_log.dart';
import '../domain/habit_planner.dart';
import 'providers/habit_providers.dart';


/// Keeps the home-screen widget and the habit reminders in step with the data.
///
/// Two jobs that belong together because they share the same trigger: whenever a
/// habit is edited or checked off, both the widget's picture of today and the
/// next alarm move. It also drains what the widget did while the app was not
/// running — the widget cannot write the app's documents, so its taps queue up
/// natively and are turned into check-ins here.
class HabitWidgetSync {
  HabitWidgetSync(this._ref);

  final Ref _ref;

  /// Whether a sync is in flight, and whether another was asked for while it ran.
  ///
  /// Adopting a widget check-in changes the log collection, which fires the
  /// listener that calls [sync] again; without this the second call would race
  /// the first one's own publish and could write a widget payload computed from
  /// the older state.
  bool _running = false;
  bool _queued = false;

  /// Applies anything the widget queued, then republishes the widget and the
  /// reminders. Safe to call as often as anything changes.
  Future<void> sync() async {
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      do {
        _queued = false;
        await _syncOnce();
      } while (_queued);
    } finally {
      _running = false;
    }
  }

  Future<void> _syncOnce() async {
    // Awaited rather than read: on a cold start these providers are still
    // loading, and a payload computed from "still loading" says there are no
    // habits at all — which erases the tick of a check-in the user has just made
    // on the home screen, and shows the wrong thing until the next publish a
    // moment later.
    final List<Habit> habits;
    final List<HabitLog> logs;
    try {
      habits = await _ref.read(habitsProvider.future);
      logs = await _ref.read(habitLogsProvider.future);
    } on Object catch (error) {
      // Nothing readable: leave the widget showing what it last knew rather than
      // replacing it with an empty picture.
      debugPrint('habit widget sync skipped: $error');
      return;
    }

    final List<HabitLog> afterAdopting = await _adoptWidgetCheckIns(habits, logs);
    final DateTime now = _ref.read(clockProvider)();

    final bool placed = await AppPlatform.updateHabitWidget(
      habitWidgetPayload(
        habits: habits,
        logs: afterAdopting,
        now: now,
        todoSub: AppStrings.habitWidgetTileTodo,
        doneSub: AppStrings.habitWidgetTileDone,
        offSub: AppStrings.habitWidgetTileOff,
        emptyTitle: AppStrings.habitWidgetEmptyTitle,
        emptyBody: AppStrings.habitWidgetEmptyBody,
        staleText: AppStrings.habitWidgetStale,
        unconfiguredText: AppStrings.habitWidgetTileUnconfigured,
        missingText: AppStrings.habitWidgetTileMissing,
      ),
    );
    // Only Android can answer this, and the habits page would otherwise offer to
    // add a widget that is already on the home screen.
    _ref.read(habitWidgetPlacedProvider.notifier).set(placed);

    await AppPlatform.syncHabitAlarms(_desiredAlarms(habits, now));

    // Last, so it draws the payload this run just published rather than the
    // empty store a fresh install starts from.
    if (kDebugMode) {
      await _selfCheckOnce();
    }
  }

  /// Whether the debug-only widget self-check has run in this process.
  bool _selfChecked = false;

  /// Draws the widget's view tree without a launcher and prints what came out.
  ///
  /// Debug builds only, and once per process. It is here because the widget is
  /// the one part of this feature that a widget test cannot reach — and on a
  /// launcher that will not host it, a device cannot reach it either — so the
  /// only way to know the layout inflates and the values bind is to ask Android
  /// to build it and report the text. See `HabitWidgetProvider.selfCheck`.
  Future<void> _selfCheckOnce() async {
    if (_selfChecked) {
      return;
    }
    _selfChecked = true;
    final Map<String, Object?> report = await AppPlatform.selfCheckHabitWidget();
    debugPrint('habit-widget-self-check: $report');
  }

  /// Turns the taps the widget queued into stored check-ins, and answers with the
  /// log as it stands afterwards.
  ///
  /// [habits] is passed in rather than re-read because that is the whole point:
  /// a habit the *loaded* list does not contain really has been deleted, while a
  /// habit missing from a list that has not loaded yet would mean a tap the user
  /// made being thrown away — and the tick they saw on the tile going with it.
  ///
  /// A check-in that already exists is left alone rather than overwritten: the
  /// note the app may have added lives on that record, and the widget has no way
  /// to know about it.
  Future<List<HabitLog>> _adoptWidgetCheckIns(
    List<Habit> habits,
    List<HabitLog> logs,
  ) async {
    final List<HabitWidgetAction> actions =
        await AppPlatform.drainHabitCheckIns();
    if (actions.isEmpty) {
      return logs;
    }
    final Set<String> known = <String>{for (final Habit habit in habits) habit.id};
    final HabitLogsController controller = _ref.read(habitLogsProvider.notifier);

    for (final HabitWidgetAction action in actions) {
      // A habit deleted while the widget still showed it: the tap is dropped
      // rather than resurrecting a habit the user removed.
      if (!known.contains(action.habitId)) {
        continue;
      }
      final bool exists = logs.any(
        (HabitLog log) =>
            log.habitId == action.habitId && log.dayKey == action.dayKey,
      );
      if (action.done && !exists) {
        await controller.checkIn(
          action.habitId,
          day: habitDayFromKey(action.dayKey),
          at: action.at,
        );
      } else if (!action.done && exists) {
        await controller.undo(action.habitId, action.dayKey);
      }
    }
    return _ref.read(habitLogsProvider).value ?? logs;
  }

  /// The habit reminders that should exist right now.
  ///
  /// A habit with no reminder time contributes nothing — that is the whole of
  /// "也可选择不提醒": there is no alarm to skip, and no default to fall back on.
  List<HabitAlarm> _desiredAlarms(List<Habit> habits, DateTime now) {
    final Map<String, Set<int>> doneDays = _ref.read(habitDoneDaysProvider);
    final AppSettings settings = _ref.read(settingsProvider);
    final int todayKey = habitDayKey(now);
    final bool ring = settings.reminderMode == ReminderMode.ring;

    final List<HabitAlarm> alarms = <HabitAlarm>[];
    for (final Habit habit in habits) {
      final int? minutes = habit.reminderMinutes;
      if (minutes == null) {
        continue;
      }
      final bool doneToday = doneDays[habit.id]?.contains(todayKey) ?? false;
      final int streak = habitStreak(
        habit: habit,
        doneDays: doneDays[habit.id] ?? const <int>{},
        today: now,
      );
      alarms.add(
        HabitAlarm(
          habitId: habit.id,
          title: habit.name,
          body: streak > 0
              ? AppStrings.habitReminderStreakBody(streak)
              : AppStrings.habitReminderBody,
          minutes: minutes,
          daysMask: habit.days,
          ring: ring,
          ringtoneUri: ring ? settings.ringtoneUri : null,
          skipToday: doneToday,
        ),
      );
    }
    return alarms;
  }
}

final Provider<HabitWidgetSync> habitWidgetSyncProvider =
    Provider<HabitWidgetSync>(
  HabitWidgetSync.new,
  name: 'habitWidgetSync',
);
