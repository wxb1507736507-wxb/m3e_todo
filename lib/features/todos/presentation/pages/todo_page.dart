import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_motion.dart';
import '../../domain/entities/todo.dart';
import '../../domain/entities/todo_filter.dart';
import '../../domain/entities/todo_stats.dart';
import '../providers/todo_providers.dart';
import '../widgets/todo_empty_state.dart';
import '../widgets/todo_list_view.dart';
import '../widgets/todo_summary_header.dart';

/// The todo screen: the summary line and the list itself.
///
/// The page owns the loading and error states so no child widget has to guard
/// against them, and it is the only place that decides which empty-state copy
/// applies. Search and sort live in the app bar (see [AppShell]) because they
/// act on the list rather than being part of it.
class TodoPage extends ConsumerWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Todo>> visible = ref.watch(visibleTodosProvider);
    final TodoFilter filter = ref.watch(todoFilterProvider);
    final TodoStats? stats = ref.watch(todoStatsProvider).value;
    final DateTime now = ref.watch(clockProvider)();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Held back until there is data: rendering zeroed counts first would
          // make the numbers visibly jump on every launch. An empty list shows
          // no summary at all — the empty state below already explains itself,
          // and "0 项进行中" above it would be noise.
          if (stats != null && stats.total > 0)
            TodoSummaryHeader(stats: stats),
          Expanded(
            child: visible.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stackTrace) => _LoadFailure(
                error: error,
                onRetry: () => ref.read(todoListProvider.notifier).reload(),
              ),
              data: (List<Todo> todos) => _content(todos, filter, stats, now),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(
    List<Todo> todos,
    TodoFilter filter,
    TodoStats? stats,
    DateTime now,
  ) {
    final bool isEmpty = todos.isEmpty;
    final Widget child = isEmpty
        ? _emptyState(filter, stats)
        : TodoListView(
            todos: todos,
            now: now,
            allowReorder: filter.allowsManualReorder,
          );

    // Cross-fading between list and placeholder softens the moment the last
    // item is ticked off. Uses the effects spring because opacity must not
    // overshoot past 1.
    return AnimatedSwitcher(
      duration: AppMotion.effectsDefault.duration,
      switchInCurve: AppMotion.effectsDefault.curve,
      switchOutCurve: AppMotion.effectsDefault.curve,
      child: KeyedSubtree(key: ValueKey<bool>(isEmpty), child: child),
    );
  }

  /// Picks the placeholder that explains *why* the list is empty.
  ///
  /// "Nothing here yet" and "nothing left to do" look identical but mean
  /// opposite things, so the copy has to distinguish them.
  Widget _emptyState(TodoFilter filter, TodoStats? stats) {
    if (filter.hasQuery) {
      return const TodoEmptyState(
        icon: Icons.search_off,
        title: AppStrings.emptySearchTitle,
        body: AppStrings.emptySearchBody,
      );
    }

    return switch (filter.status) {
      TodoStatusFilter.completed => const TodoEmptyState(
          icon: Icons.done_all,
          title: AppStrings.emptyCompletedTitle,
          body: AppStrings.emptyCompletedBody,
        ),
      TodoStatusFilter.active when (stats?.total ?? 0) > 0 =>
        const TodoEmptyState(
          icon: Icons.celebration_outlined,
          title: AppStrings.emptyActiveTitle,
          body: AppStrings.emptyActiveBody,
        ),
      _ => const TodoEmptyState(
          icon: Icons.playlist_add,
          title: AppStrings.emptyAllTitle,
          body: AppStrings.emptyAllBody,
        ),
    };
  }
}

/// Shown when the collection could not be read at all.
class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    // Scrollable for the same reason as TodoEmptyState: a phone with the keyboard
    // open can leave this card less height than its own content needs, and an
    // error message is exactly the wrong thing to have overflow off-screen.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  color: colors.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.error_outline,
                              color: colors.onErrorContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                AppStrings.loadFailedTitle,
                                style: text.titleLarge?.copyWith(
                                  color: colors.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.loadFailedBody,
                          style: text.bodyMedium?.copyWith(
                            color: colors.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$error',
                          style: text.bodySmall?.copyWith(
                            color: colors.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh),
                            label: const Text(AppStrings.retry),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
