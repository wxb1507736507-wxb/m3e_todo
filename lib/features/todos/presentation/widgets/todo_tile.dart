import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../domain/entities/todo.dart';
import '../../domain/entities/todo_priority.dart';

/// A single row in the todo list.
///
/// Deliberately a plain [StatelessWidget] that takes callbacks instead of
/// reading providers. That keeps it cheap to rebuild, trivial to render in a
/// widget test, and independent of how the controller is wired.
class TodoTile extends StatelessWidget {
  const TodoTile({
    required this.todo,
    required this.now,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.dragIndex,
    super.key,
  });

  final Todo todo;

  /// The current time, passed in rather than read from the clock so every row
  /// in a single frame agrees on what "today" means.
  final DateTime now;

  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// When non-null, the row shows a drag handle that reorders at this index.
  /// Present only while the list is in manual sort order, because dragging is
  /// meaningless once a rule decides the order.
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool completed = todo.isCompleted;

    return Card(
      color: completed ? colors.surfaceContainerLowest : colors.surfaceContainerLow,
      child: InkWell(
        onTap: onEdit,
        borderRadius: AppShapes.radius(AppShapes.large),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Checkbox(
                value: completed,
                onChanged: (_) => onToggle(),
                semanticLabel: completed
                    ? AppStrings.actionMarkIncomplete
                    : AppStrings.actionMarkComplete,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AnimatedDefaultTextStyle(
                        duration: AppMotion.effectsFast.duration,
                        curve: AppMotion.effectsFast.curve,
                        style: (text.titleMedium ?? const TextStyle()).copyWith(
                          color: completed
                              ? colors.onSurfaceVariant
                              : colors.onSurface,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: colors.onSurfaceVariant,
                        ),
                        child: Text(todo.title),
                      ),
                      if (todo.hasNotes) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          todo.notes!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (_hasMeta(completed)) ...<Widget>[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            if (!completed && todo.dueDate != null)
                              _DueChip(todo: todo, now: now),
                            if (todo.priority != TodoPriority.normal)
                              _PriorityChip(priority: todo.priority),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: Tooltip(
                    message: AppStrings.sortManual,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              _ActionsMenu(onEdit: onEdit, onDelete: onDelete),
            ],
          ),
        ),
      ),
    );
  }

  /// The meta row is skipped entirely for a completed todo with no priority,
  /// which keeps finished work visually quiet.
  bool _hasMeta(bool completed) {
    final bool showDue = !completed && todo.dueDate != null;
    final bool showPriority = todo.priority != TodoPriority.normal;
    return showDue || showPriority;
  }
}

class _DueChip extends StatelessWidget {
  const _DueChip({required this.todo, required this.now});

  final Todo todo;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final bool overdue = todo.isOverdue(now);
    final bool today = todo.isDueToday(now);

    final Color background = overdue
        ? colors.errorContainer
        : today
            ? colors.tertiaryContainer
            : colors.surfaceContainerHighest;
    final Color foreground = overdue
        ? colors.onErrorContainer
        : today
            ? colors.onTertiaryContainer
            : colors.onSurfaceVariant;

    final DateTime due = todo.dueDate!;
    final String label = switch (todo.daysUntilDue(now)) {
      final int days when days < 0 => AppStrings.dueOverdue,
      _ => AppDateFormatter.dayLabel(due, now),
    };

    return _MetaPill(
      icon: overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
      label: label,
      background: background,
      foreground: foreground,
      labelStyle: text.labelMedium,
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final TodoPriority priority;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final (Color background, Color foreground, String label) = switch (priority) {
      TodoPriority.high => (
          colors.errorContainer,
          colors.onErrorContainer,
          AppStrings.priorityHigh,
        ),
      TodoPriority.normal => (
          colors.secondaryContainer,
          colors.onSecondaryContainer,
          AppStrings.priorityNormal,
        ),
      TodoPriority.low => (
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
          AppStrings.priorityLow,
        ),
    };

    return _MetaPill(
      icon: Icons.flag_outlined,
      label: label,
      background: background,
      foreground: foreground,
      labelStyle: text.labelMedium,
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.labelStyle,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppShapes.radius(AppShapes.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(label, style: labelStyle?.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: <Widget>[
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: onEdit,
          child: const Text(AppStrings.actionEdit),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
          child: const Text(AppStrings.actionDelete),
        ),
      ],
      builder: (
        BuildContext context,
        MenuController controller,
        Widget? child,
      ) {
        return IconButton(
          icon: const Icon(Icons.more_vert),
          tooltip: AppStrings.moreActions,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }
}
