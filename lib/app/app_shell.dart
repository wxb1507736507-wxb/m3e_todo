import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_strings.dart';
import '../core/platform/app_platform.dart';
import '../features/calendar/domain/entities/special_day.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/calendar/presentation/providers/special_day_providers.dart';
import '../features/notifications/reminder_coordinator.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/settings_controller.dart';
import '../features/settings/presentation/settings_sheet.dart';
import '../features/todos/domain/entities/todo.dart';
import '../features/todos/domain/entities/todo_filter.dart';
import '../features/todos/domain/entities/todo_stats.dart';
import '../features/todos/presentation/pages/todo_page.dart';
import '../features/todos/presentation/providers/todo_providers.dart';
import '../features/todos/presentation/widgets/todo_editor_sheet.dart';
import '../features/todos/presentation/widgets/todo_toolbar.dart';
import 'app_background.dart';

/// Width at or above which the navigation rail replaces the bottom bar.
///
/// 720dp is roughly where a desktop window can afford a 80dp rail without
/// squeezing the list, and it keeps the layout sane if the window is dragged
/// very narrow.
const double kRailBreakpoint = 720;

/// The application frame: navigation, app bar, shortcuts and the new-todo
/// action.
///
/// Navigation has four destinations: the three status filters plus the calendar
/// review. Selecting a status shows the list; selecting the calendar swaps the
/// body for [CalendarPage] while leaving the filters untouched.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const List<TodoStatusFilter> _statuses = <TodoStatusFilter>[
    TodoStatusFilter.all,
    TodoStatusFilter.active,
    TodoStatusFilter.completed,
  ];

  /// Index of the calendar pseudo-destination (after the three statuses).
  static const int _calendarIndex = 3;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(reminderCoordinatorProvider).sync());
      // Ask for the notification permission up front on Android 13+: a
      // reminder that cannot show itself is worse than one more dialog at
      // first launch.
      unawaited(_ensureNotificationPermission());
    });
  }

  Future<void> _ensureNotificationPermission() async {
    if (!AppPlatform.isAndroid) {
      return;
    }
    if (!await AppPlatform.notificationsEnabled()) {
      await AppPlatform.requestNotificationPermission();
    }
  }

  void _primaryAction() => unawaited(showTodoEditor(context));

  void _focusSearch() => ref.read(searchFocusNodeProvider).requestFocus();

  Future<void> _clearCompleted(int completedCount) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text(AppStrings.clearCompletedTitle),
        content: Text(AppStrings.clearCompletedBody(completedCount)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final int removed =
          await ref.read(todoListProvider.notifier).clearCompleted();
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.clearedCompleted(removed))),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${AppStrings.saveFailed}：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reminder schedule wiring: listening in build (rather than initState) is
    // the Riverpod-blessed way for a StatefulWidget, and both listeners below
    // only fire on actual changes.
    ref.listen<AsyncValue<List<Todo>>>(
      todoListProvider,
      (AsyncValue<List<Todo>>? previous, AsyncValue<List<Todo>> next) {
        if (next.hasValue) {
          unawaited(ref.read(reminderCoordinatorProvider).sync());
        }
      },
    );
    // The personal dates are reminders too: a birthday entered once has to
    // announce itself every year without being maintained.
    ref.listen<AsyncValue<List<SpecialDay>>>(
      specialDaysProvider,
      (AsyncValue<List<SpecialDay>>? previous, AsyncValue<List<SpecialDay>> next) {
        if (next.hasValue) {
          unawaited(ref.read(reminderCoordinatorProvider).sync());
        }
      },
    );
    ref.listen<AppSettings>(
      settingsProvider,
      (AppSettings? previous, AppSettings next) {
        if (previous == null ||
            previous.reminderMode != next.reminderMode ||
            previous.ringtoneUri != next.ringtoneUri) {
          unawaited(ref.read(reminderCoordinatorProvider).resync());
        }
      },
    );

    final TodoStatusFilter status = ref.watch(
      todoFilterProvider.select((TodoFilter filter) => filter.status),
    );
    final TodoStats? stats = ref.watch(todoStatsProvider).value;
    final AppSettings settings = ref.watch(settingsProvider);

    // The selected destination only maps to a status for the first three
    // entries; the calendar keeps whichever filter was last active.
    if (_selectedIndex < _statuses.length) {
      final int statusIndex = _statuses.indexOf(status);
      if (statusIndex >= 0) {
        _selectedIndex = statusIndex;
      }
    }

    // Shortcuts are registered on the shell rather than on individual widgets so
    // they work wherever focus happens to be. While a modal sheet is open the
    // route owns focus, so these correctly stay inactive.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _primaryAction,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool useRail = constraints.maxWidth >= kRailBreakpoint;

            return AppBackground(
              imagePath: settings.backgroundImage,
              dim: settings.backgroundDim,
              child: Scaffold(
                appBar: AppBar(
                  titleSpacing: 16,
                  // The title follows the destination, so the calendar says so
                  // instead of leaving the user to infer it from the grid. On
                  // the list, the title *is* the search field: searching and
                  // sorting are what the user does to the list, so they sit on
                  // the top line with the settings button rather than costing a
                  // row of their own above the first todo.
                  title: _selectedIndex == _calendarIndex
                      ? const Text(AppStrings.calendarTitle)
                      : const TodoSearchField(),
                  actions: <Widget>[
                    if (_selectedIndex != _calendarIndex)
                      const TodoSortButton(),
                    if ((stats?.completed ?? 0) > 0)
                      IconButton(
                        icon: const Icon(Icons.cleaning_services_outlined),
                        tooltip: AppStrings.clearCompleted,
                        onPressed: () => unawaited(
                          _clearCompleted(stats!.completed),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: AppStrings.settingsTooltip,
                      onPressed: () => unawaited(showSettingsSheet(context)),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: useRail
                    ? Row(
                        children: <Widget>[
                          _buildRail(context, stats),
                          const VerticalDivider(width: 1),
                          Expanded(child: _buildBody()),
                        ],
                      )
                    : _buildBody(),
                bottomNavigationBar:
                    useRail ? null : _buildBottomBar(stats),
                floatingActionButton: FloatingActionButton.extended(
                  onPressed: _primaryAction,
                  icon: const Icon(Icons.add),
                  label: const Text(AppStrings.newTodo),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody() =>
      _selectedIndex == _calendarIndex ? const CalendarPage() : const TodoPage();

  void _selectDestination(int index) {
    if (index == _calendarIndex) {
      setState(() => _selectedIndex = index);
      return;
    }
    setState(() => _selectedIndex = index);
    ref.read(todoFilterProvider.notifier).setStatus(_statuses[index]);
  }

  Widget _buildRail(BuildContext context, TodoStats? stats) {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _selectDestination,
      labelType: NavigationRailLabelType.all,
      destinations: <NavigationRailDestination>[
        NavigationRailDestination(
          icon: _badged(const Icon(Icons.inbox_outlined), stats?.total ?? 0),
          selectedIcon: _badged(const Icon(Icons.inbox), stats?.total ?? 0),
          label: const Text(AppStrings.navAll),
        ),
        NavigationRailDestination(
          icon: _badged(
            const Icon(Icons.schedule_outlined),
            stats?.active ?? 0,
          ),
          selectedIcon: _badged(
            const Icon(Icons.schedule),
            stats?.active ?? 0,
          ),
          label: const Text(AppStrings.navActive),
        ),
        NavigationRailDestination(
          icon: _badged(
            const Icon(Icons.check_circle_outline),
            stats?.completed ?? 0,
          ),
          selectedIcon: _badged(
            const Icon(Icons.check_circle),
            stats?.completed ?? 0,
          ),
          label: const Text(AppStrings.navCompleted),
        ),

        const NavigationRailDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: Text(AppStrings.navCalendar),
        ),
      ],
    );
  }

  Widget _buildBottomBar(TodoStats? stats) {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _selectDestination,
      destinations: <Widget>[
        NavigationDestination(
          icon: _badged(const Icon(Icons.inbox_outlined), stats?.total ?? 0),
          selectedIcon: _badged(const Icon(Icons.inbox), stats?.total ?? 0),
          label: AppStrings.navAll,
        ),
        NavigationDestination(
          icon: _badged(
            const Icon(Icons.schedule_outlined),
            stats?.active ?? 0,
          ),
          selectedIcon: _badged(
            const Icon(Icons.schedule),
            stats?.active ?? 0,
          ),
          label: AppStrings.navActive,
        ),
        NavigationDestination(
          icon: _badged(
            const Icon(Icons.check_circle_outline),
            stats?.completed ?? 0,
          ),
          selectedIcon: _badged(
            const Icon(Icons.check_circle),
            stats?.completed ?? 0,
          ),
          label: AppStrings.navCompleted,
        ),

        const NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: AppStrings.navCalendar,
        ),
      ],
    );
  }

  /// Wraps [icon] in a count badge, or returns it untouched when there is
  /// nothing to report &mdash; a "0" badge is noise, not information.
  static Widget _badged(Widget icon, int count) {
    if (count <= 0) {
      return icon;
    }
    return Badge(label: Text('$count'), child: icon);
  }
}
