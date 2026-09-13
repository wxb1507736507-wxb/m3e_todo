import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/platform/app_platform.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../domain/entities/todo.dart';
import '../../domain/entities/todo_attachment.dart';
import '../../domain/entities/todo_priority.dart';
import 'attachment_actions.dart';

/// A single row in the todo list.
///
/// Deliberately a plain [StatefulWidget] that takes callbacks instead of
/// reading providers. That keeps it cheap to rebuild, trivial to render in a
/// widget test, and independent of how the controller is wired. The only local
/// state is whether the subtask checklist is expanded.
///
/// Reordering is started by a *long press anywhere on the row*: the wrapping
/// [ReorderableDelayedDragStartListener] in [TodoListView] owns that gesture,
/// so this widget needs no drag affordance at all.
class TodoTile extends StatefulWidget {
  const TodoTile({
    required this.todo,
    required this.now,
    required this.onToggle,
    required this.onToggleSubtask,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final Todo todo;

  /// The current time, passed in rather than read from the clock so every row
  /// in a single frame agrees on what "today" means.
  final DateTime now;

  final VoidCallback onToggle;
  final ValueChanged<String> onToggleSubtask;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<TodoTile> createState() => _TodoTileState();
}

class _TodoTileState extends State<TodoTile> {
  bool _subtasksExpanded = false;

  @override
  void didUpdateWidget(TodoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An edited todo may have lost all subtasks; collapse so no stale empty
    // section lingers.
    if (widget.todo.hasSubtasks != oldWidget.todo.hasSubtasks &&
        !widget.todo.hasSubtasks) {
      _subtasksExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Todo todo = widget.todo;
    final bool completed = todo.isCompleted;
    final Color accent = todo.accentColor == null
        ? colors.surfaceContainerLow
        : Color(todo.accentColor!);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      // Custom background: the user's accent colour, optionally with a dimmed
      // image underneath. Both fall back to the theme surface.
      color: todo.backgroundImage == null ? accent : null,
      child: Stack(
        children: <Widget>[
          if (todo.backgroundImage != null && !kIsWeb)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.file(
                    File(todo.backgroundImage!),
                    fit: BoxFit.cover,
                    // Bound the decode size: tiles are a couple of hundred
                    // logical pixels tall, so a full-resolution photo would
                    // waste memory and time for nothing.
                    cacheWidth: 640,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  // The photo is dimmed so the text keeps its contrast no matter
                  // how bright the picture is — a full-strength photo would
                  // wreck both the light and the dark theme.
                  //
                  // A translucent scrim rather than `Opacity`: an opacity group
                  // makes the tile allocate an offscreen layer and blend it back
                  // (`saveLayer`), once per tile, on every frame the list moves.
                  // Washing the image out with a flat fill is a single extra
                  // draw with no layer at all, and looks the same.
                  ColoredBox(
                    color: colors.surface.withValues(alpha: 0.75),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: widget.onEdit,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Checkbox(
                    value: completed,
                    onChanged: (_) => widget.onToggle(),
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
                            style:
                                (text.titleMedium ?? const TextStyle()).copyWith(
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
                          if (todo.hasSubtasks) ...<Widget>[
                            const SizedBox(height: 8),
                            _SubtaskHeader(
                              done: todo.subtaskProgress().$1,
                              total: todo.subtaskProgress().$2,
                              expanded: _subtasksExpanded,
                              onToggleExpanded: () => setState(
                                () => _subtasksExpanded = !_subtasksExpanded,
                              ),
                            ),
                            if (_subtasksExpanded)
                              _SubtaskChecklist(
                                todo: todo,
                                onToggle: widget.onToggleSubtask,
                              ),
                          ],
                          if (todo.hasAttachments) ...<Widget>[
                            const SizedBox(height: 8),
                            _AttachmentRow(
                              attachments: todo.attachments,
                            ),
                          ],
                          if (_hasMeta(completed)) ...<Widget>[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                if (!completed && todo.dueDate != null)
                                  _DueChip(todo: todo, now: widget.now),
                                if (todo.priority != TodoPriority.normal)
                                  _PriorityChip(priority: todo.priority),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _ActionsMenu(onEdit: widget.onEdit, onDelete: widget.onDelete),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The meta row is skipped entirely for a completed todo with no priority,
  /// which keeps finished work visually quiet.
  bool _hasMeta(bool completed) {
    final bool showDue = !completed && widget.todo.dueDate != null;
    final bool showPriority = widget.todo.priority != TodoPriority.normal;
    return showDue || showPriority;
  }
}

class _SubtaskHeader extends StatelessWidget {
  const _SubtaskHeader({
    required this.done,
    required this.total,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final int done;
  final int total;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onToggleExpanded,
      borderRadius: AppShapes.radius(AppShapes.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              '${AppStrings.subtasksLabel} ${AppStrings.subtaskProgress(done, total)}',
              style: text.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtaskChecklist extends StatelessWidget {
  const _SubtaskChecklist({required this.todo, required this.onToggle});

  final Todo todo;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Column(
        children: <Widget>[
          for (final subtask in todo.subtasks)
            InkWell(
              onTap: () => onToggle(subtask.id),
              borderRadius: AppShapes.radius(AppShapes.small),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Icon(
                      subtask.isCompleted
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: subtask.isCompleted
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        subtask.title,
                        style: text.bodyMedium?.copyWith(
                          color: subtask.isCompleted
                              ? colors.onSurfaceVariant
                              : colors.onSurface,
                          decoration: subtask.isCompleted
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Thumbnail strip; tapping a thumb hands the file to the system viewer.
class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachments});

  final List<TodoAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final TodoAttachment attachment in attachments)
          InkWell(
            onTap: () => unawaited(
              _open(context, attachment),
            ),
            borderRadius: BorderRadius.circular(8),
            child: AttachmentThumb(attachment: attachment),
          ),
      ],
    );
  }

  static Future<void> _open(
    BuildContext context,
    TodoAttachment attachment,
  ) async {
    final bool opened =
        await AppPlatform.openAttachment(attachment.path, attachment.mime);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.attachmentOpenFailed)),
      );
    }
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
