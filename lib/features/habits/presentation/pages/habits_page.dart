import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/platform/app_platform.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/utils/calendar.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/habit_planner.dart';
import '../habit_permissions.dart';
import '../habit_widget_sync.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_checkin_sheet.dart';
import '../widgets/habit_editor_sheet.dart';
import '../widgets/habit_history_sheet.dart';
import '../widgets/habit_row.dart';

/// The 打卡 destination: what to check off today, and the habits themselves.
class HabitsPage extends ConsumerStatefulWidget {
  const HabitsPage({super.key});

  @override
  ConsumerState<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends ConsumerState<HabitsPage> {
  /// The open request already acted on, so one request opens one sheet.
  String? _openedFor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    // The widget's ＋ button lands here: it asks for one habit's editor, and
    // clearing the request afterwards is what stops it from reopening on every
    // rebuild.
    //
    // Watched rather than listened to because the request usually arrives
    // *before* this page exists: the shell routes here and sets the request in
    // the same breath, and a change-only listener registered afterwards would
    // never hear about it. `_openedFor` is what keeps one request from opening
    // two sheets when several builds are queued behind it.
    final String? openRequest = ref.watch(pendingHabitOpenProvider);
    if (openRequest != null && openRequest != _openedFor) {
      _openedFor = openRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final Habit? habit = ref.read(habitByIdProvider(openRequest));
        ref.read(pendingHabitOpenProvider.notifier).clear();
        if (habit != null) {
          unawaited(showHabitCheckInSheet(context, habit: habit));
        }
      });
    }

    final List<Habit> habits = ref.watch(habitsProvider).value ?? const <Habit>[];
    final List<HabitDayStatus> today = ref.watch(todaysHabitsProvider);
    final Map<String, Set<int>> doneDays = ref.watch(habitDoneDaysProvider);
    final DateTime now = ref.watch(clockProvider)();
    final int todayKey = habitDayKey(now);
    final Set<String> dueIds = <String>{
      for (final HabitDayStatus status in today) status.habit.id,
    };
    final List<Habit> others = <Habit>[
      for (final Habit habit in habits)
        if (!dueIds.contains(habit.id)) habit,
    ];

    if (habits.isEmpty) {
      return _emptyState(context);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        // Only when it matters: a habit that reminds and an app that cannot. A
        // permission warning on a screen with no reminders would be nagging.
        if (habits.any((Habit habit) => habit.reminds))
          _ReminderPermissionBanner(
            status: ref.watch(habitPermissionStatusProvider),
          ),
        _TodayHeader(
          dueCount: today.length,
          doneCount: today.where((HabitDayStatus s) => s.done).length,
        ),
        const SizedBox(height: 10),
        if (today.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              AppStrings.habitTodayNone,
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          )
        else
          for (final HabitDayStatus status in today)
            _row(
              habit: status.habit,
              doneToday: status.done,
              dueToday: true,
              doneDays: doneDays[status.habit.id] ?? const <int>{},
              todayKey: todayKey,
              now: now,
            ),
        if (others.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          Text(
            AppStrings.habitOthers,
            style: text.labelLarge?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final Habit habit in others)
            _row(
              habit: habit,
              doneToday:
                  (doneDays[habit.id] ?? const <int>{}).contains(todayKey),
              dueToday: false,
              doneDays: doneDays[habit.id] ?? const <int>{},
              todayKey: todayKey,
              now: now,
            ),
        ],
        // Only where there is a home screen to put it on: an offer that cannot
        // be taken is worse than no offer.
        if (AppPlatform.isAndroid) ...<Widget>[
          const SizedBox(height: 18),
          _widgetCard(context),
        ],
      ],
    );
  }

  Widget _row({
    required Habit habit,
    required bool doneToday,
    required bool dueToday,
    required Set<int> doneDays,
    required int todayKey,
    required DateTime now,
  }) {
    return HabitRow(
      habit: habit,
      doneToday: doneToday,
      dueToday: dueToday,
      streak: habitStreak(habit: habit, doneDays: doneDays, today: now),
      recentDays: habitRecentDays(
        habit: habit,
        doneDays: doneDays,
        today: now,
      ),
      onToggle: () => unawaited(_toggle(habit, doneToday)),
      onOpen: () => unawaited(showHabitCheckInSheet(context, habit: habit)),
      onMenu: () => unawaited(_menu(habit)),
    );
  }

  /// Checks off, or takes back, today's entry — the one-tap path the widget also
  /// uses.
  Future<void> _toggle(Habit habit, bool doneToday) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final HabitLogsController controller = ref.read(habitLogsProvider.notifier);
    final DateTime now = ref.read(clockProvider)();
    if (doneToday) {
      await controller.undo(habit.id, habitDayKey(now));
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.habitUndoneToast(habit.name))),
      );
    } else {
      await controller.checkIn(habit.id, day: startOfDay(now));
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.habitCheckedInToast(habit.name))),
      );
    }
  }

  Future<void> _menu(Habit habit) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text(AppStrings.habitCheckInTitle),
              onTap: () => Navigator.of(sheetContext).pop('checkin'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text(AppStrings.habitEdit),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text(AppStrings.habitHistory),
              onTap: () => Navigator.of(sheetContext).pop('history'),
            ),
            // One widget shows one habit, so this is where a tile for *this*
            // habit comes from — and the tile it makes skips the question of
            // which habit it is for.
            if (AppPlatform.isAndroid)
              ListTile(
                leading: const Icon(Icons.add_to_home_screen),
                title: const Text(AppStrings.habitWidgetAdd),
                onTap: () => Navigator.of(sheetContext).pop('widget'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case 'checkin':
        await showHabitCheckInSheet(context, habit: habit);
      case 'edit':
        await showHabitEditorSheet(context, existing: habit);
      case 'history':
        await showHabitHistorySheet(context, habit: habit);
      case 'widget':
        await _pinWidget(habit: habit);
    }
  }

  /// The card that explains the widget and puts one on the home screen.
  ///
  /// Hidden entirely where there is no widget support, rather than shown
  /// disabled: an offer that cannot be taken is worse than no offer.
  Widget _widgetCard(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool placed = ref.watch(habitWidgetPlacedProvider);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: <Widget>[
            Icon(
              placed ? Icons.widgets : Icons.add_to_home_screen,
              color: colors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(AppStrings.habitWidgetSection, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    placed
                        ? AppStrings.habitWidgetWhereHint
                        : AppStrings.habitWidgetAddHint,
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_pinWidget()),
              child: Text(
                placed ? AppStrings.habitWidgetAddMore : AppStrings.habitWidgetAdd,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Puts a widget on the home screen, for [habit] when one was named.
  ///
  /// Without a habit the system's own configuration screen asks which one; with
  /// one, that question is already answered.
  Future<void> _pinWidget({Habit? habit}) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool requested =
        await AppPlatform.requestHabitWidgetPin(habitId: habit?.id);
    if (!mounted) {
      return;
    }
    if (!requested) {
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.habitWidgetUnsupported)),
      );
      return;
    }
    // Whether a widget now exists is decided by the launcher, outside this app,
    // and not every launcher honours the request — the realme build used to
    // develop this one opens its confirmation and drops it. So the answer is
    // read back rather than assumed, and the user is told how to add it by hand
    // when the request went nowhere. Promising a dialog that never appears is
    // worse than admitting the step is manual.
    await Future<void>.delayed(const Duration(seconds: 3));
    await ref.read(habitWidgetSyncProvider).sync();
    if (!mounted) {
      return;
    }
    final bool placed = ref.read(habitWidgetPlacedProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          placed
              ? AppStrings.habitWidgetAdded
              : AppStrings.habitWidgetManualHint,
        ),
        duration: const Duration(seconds: 8),
        // Several launchers gate placing a widget behind a permission of their
        // own, which no app can request — so the page it lives on is opened
        // instead of describing where to find it.
        action: placed
            ? null
            : SnackBarAction(
                label: AppStrings.habitOpenSettings,
                onPressed: () => unawaited(AppPlatform.openAppSettings()),
              ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.event_available, size: 52, color: colors.outline),
            const SizedBox(height: 14),
            Text(AppStrings.habitEmptyTitle, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              AppStrings.habitEmptyBody,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// The warning that a habit's reminder cannot reach the user, with the one
/// action that fixes it.
///
/// Shown rather than silently logged because the failure is invisible by
/// nature: a reminder that never arrives looks exactly like a reminder that was
/// never set.
class _ReminderPermissionBanner extends ConsumerWidget {
  const _ReminderPermissionBanner({required this.status});

  final AsyncValue<HabitPermissionStatus> status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HabitPermissionStatus? value = status.value;
    // Still loading, unsupported, or fine: nothing to say.
    if (value == null || value.remindersWork) {
      return const SizedBox.shrink();
    }
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.errorContainer,
        borderRadius: AppShapes.radius(AppShapes.small),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.notifications_off_outlined, color: colors.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value.notifications
                      ? AppStrings.habitExactAlarmHint
                      : AppStrings.habitNotificationPermissionHint,
                  style: text.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => unawaited(
                  openReminderPermissionSettings(value),
                ),
                child: const Text(AppStrings.habitOpenSettings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `今天 2/3`, plus a bar that fills as the day goes.
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.dueCount, required this.doneCount});

  final int dueCount;
  final int doneCount;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final double ratio = dueCount == 0 ? 0 : doneCount / dueCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: AppShapes.radius(AppShapes.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(AppStrings.habitToday, style: text.titleMedium),
              const Spacer(),
              if (dueCount > 0)
                Text(
                  AppStrings.habitWidgetCount(doneCount, dueCount),
                  style: text.labelLarge?.copyWith(color: colors.primary),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: colors.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}
