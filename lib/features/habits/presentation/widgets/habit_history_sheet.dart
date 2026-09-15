import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/habit_planner.dart';
import '../providers/habit_providers.dart';

/// Opens the check-in history for one habit.
Future<void> showHabitHistorySheet(
  BuildContext context, {
  required Habit habit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => HabitHistorySheet(habit: habit),
  );
}

/// Every check-in of one habit, newest first, with the notes that were written.
///
/// The records are the point of the whole feature, so they are shown as they
/// were written and can be deleted one at a time — a wrong entry is not a reason
/// to throw away the habit.
class HabitHistorySheet extends ConsumerWidget {
  const HabitHistorySheet({required this.habit, super.key});

  final Habit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final List<HabitLog> logs = ref.watch(habitLogsOfProvider(habit.id));
    final DateTime now = ref.read(clockProvider)();
    final Set<int> doneDays =
        ref.watch(habitDoneDaysProvider)[habit.id] ?? const <int>{};

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(habit.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${habit.name} · ${AppStrings.habitHistory}',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        AppStrings.habitTotalTimes(habitTotal(doneDays)),
                        if (habitStreak(
                              habit: habit,
                              doneDays: doneDays,
                              today: now,
                            ) >
                            0)
                          AppStrings.habitStreakDays(
                            habitStreak(
                              habit: habit,
                              doneDays: doneDays,
                              today: now,
                            ),
                          ),
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  AppStrings.habitHistoryEmpty,
                  style: text.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ConstrainedBox(
              // Tall enough to be useful, short enough that the sheet still
              // reads as a sheet rather than a page.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: logs.length,
                itemBuilder: (BuildContext context, int index) {
                  final HabitLog log = logs[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      AppDateFormatter.calendarDate(log.day, now),
                      style: text.labelLarge,
                    ),
                    subtitle: log.hasNote ? Text(log.note!) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: AppStrings.actionDelete,
                      onPressed: () => unawaited(
                        ref
                            .read(habitLogsProvider.notifier)
                            .undo(log.habitId, log.dayKey),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
