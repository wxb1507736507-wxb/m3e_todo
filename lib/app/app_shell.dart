import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_strings.dart';
import '../features/settings/presentation/appearance_sheet.dart';
import '../features/todos/domain/entities/todo_filter.dart';
import '../features/todos/domain/entities/todo_stats.dart';
import '../features/todos/presentation/pages/todo_page.dart';
import '../features/todos/presentation/providers/todo_providers.dart';
import '../features/todos/presentation/widgets/todo_editor_sheet.dart';

/// Width at or above which the navigation rail replaces the bottom bar.
///
/// 720dp is roughly where a desktop window can afford a 80dp rail without
/// squeezing the list, and it keeps the layout sane if the window is dragged
/// very narrow.
const double kRailBreakpoint = 720;

/// The application frame: navigation, app bar, shortcuts and the new-todo
/// action.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Order of the navigation destinations, and the single mapping from index to
  /// status. Driving the rail and the bottom bar from one list is what stops the
  /// two from disagreeing on a narrow window.
  static const List<TodoStatusFilter> _statuses = <TodoStatusFilter>[
    TodoStatusFilter.all,
    TodoStatusFilter.active,
    TodoStatusFilter.completed,
  ];

  void _createTodo() => unawaited(showTodoEditor(context));

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
    final TodoStatusFilter status = ref.watch(
      todoFilterProvider.select((TodoFilter filter) => filter.status),
    );
    final TodoStats? stats = ref.watch(todoStatsProvider).value;
    final int selectedIndex = _statuses.indexOf(status);

    // Shortcuts are registered on the shell rather than on individual widgets so
    // they work wherever focus happens to be. While a modal sheet is open the
    // route owns focus, so these correctly stay inactive.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _createTodo,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool useRail = constraints.maxWidth >= kRailBreakpoint;

            return Scaffold(
              appBar: AppBar(
                title: const Text(AppStrings.appTitle),
                actions: <Widget>[
                  if ((stats?.completed ?? 0) > 0)
                    IconButton(
                      icon: const Icon(Icons.cleaning_services_outlined),
                      tooltip: AppStrings.clearCompleted,
                      onPressed: () => unawaited(
                        _clearCompleted(stats!.completed),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.palette_outlined),
                    tooltip: AppStrings.appearanceTooltip,
                    onPressed: () => unawaited(showAppearanceSheet(context)),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: useRail
                  ? Row(
                      children: <Widget>[
                        _buildRail(context, selectedIndex, stats),
                        const VerticalDivider(width: 1),
                        const Expanded(child: TodoPage()),
                      ],
                    )
                  : const TodoPage(),
              bottomNavigationBar:
                  useRail ? null : _buildBottomBar(selectedIndex, stats),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: _createTodo,
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.newTodo),
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectStatus(int index) {
    ref.read(todoFilterProvider.notifier).setStatus(_statuses[index]);
  }

  Widget _buildRail(
    BuildContext context,
    int selectedIndex,
    TodoStats? stats,
  ) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: _selectStatus,
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
      ],
    );
  }

  Widget _buildBottomBar(int selectedIndex, TodoStats? stats) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: _selectStatus,
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
