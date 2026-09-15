import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../domain/entities/habit.dart';
import '../../domain/habit_planner.dart';

/// One habit in the list: what it is, when it is due, how the last week went,
/// and the button that checks it off.
///
/// The circle checks off in one tap; the rest of the row opens the check-in
/// editor, where a note can be written. Two different intents, two different
/// targets — making the whole row check in would punish anyone who wanted to
/// write something.
class HabitRow extends StatelessWidget {
  const HabitRow({
    required this.habit,
    required this.doneToday,
    required this.streak,
    required this.recentDays,
    required this.dueToday,
    required this.onToggle,
    required this.onOpen,
    required this.onMenu,
    super.key,
  });

  final Habit habit;
  final bool doneToday;
  final int streak;

  /// The last seven days, oldest first.
  final List<HabitDayMark> recentDays;

  /// Whether today is one of the habit's own days.
  final bool dueToday;

  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent =
        habit.color == null ? colors.primary : Color(habit.color!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.surfaceContainerHigh.withValues(
          alpha: dueToday ? 1 : 0.5,
        ),
        borderRadius: AppShapes.radius(AppShapes.small),
        child: InkWell(
          onTap: onOpen,
          borderRadius: AppShapes.radius(AppShapes.small),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Text(habit.emoji, style: const TextStyle(fontSize: 19)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        habit.name,
                        style: text.titleMedium?.copyWith(
                          decoration:
                              doneToday ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        <String>[
                          habit.scheduleLabel,
                          if (habit.reminderLabel != null)
                            habit.reminderLabel!,
                          if (streak > 0) AppStrings.habitStreakDays(streak),
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _RecentMarks(marks: recentDays, accent: accent),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onMenu,
                  icon: const Icon(Icons.more_vert),
                  tooltip: AppStrings.moreActions,
                ),
                // The one-tap path. Its size and position are the whole reason
                // the widget can be a widget and not a form.
                Semantics(
                  button: true,
                  selected: doneToday,
                  child: IconButton(
                    onPressed: onToggle,
                    iconSize: 30,
                    tooltip: doneToday
                        ? AppStrings.habitUndo
                        : AppStrings.habitCheckIn,
                    icon: Icon(
                      doneToday
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: doneToday ? accent : colors.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The last seven days as small dots: kept, missed, or not asked of you.
class _RecentMarks extends StatelessWidget {
  const _RecentMarks({required this.marks, required this.accent});

  final List<HabitDayMark> marks;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        for (final HabitDayMark mark in marks)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (mark) {
                  HabitDayMark.done => accent,
                  HabitDayMark.missed => colors.error.withValues(alpha: 0.55),
                  HabitDayMark.notDue => colors.outlineVariant,
                },
              ),
            ),
          ),
      ],
    );
  }
}
