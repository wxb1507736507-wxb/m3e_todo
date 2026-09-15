import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../domain/entities/habit.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/habit_planner.dart';
import '../providers/habit_providers.dart';
import 'habit_history_sheet.dart';

/// Opens the check-in sheet for one habit: today's check-in, with an optional
/// written note.
///
/// This is what the home-screen widget's ＋ button opens, which is why [dayKey]
/// can be passed in: the widget knows which day it was showing.
Future<void> showHabitCheckInSheet(
  BuildContext context, {
  required Habit habit,
  int? dayKey,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => HabitCheckInSheet(habit: habit, dayKey: dayKey),
  );
}

class HabitCheckInSheet extends ConsumerStatefulWidget {
  const HabitCheckInSheet({required this.habit, this.dayKey, super.key});

  final Habit habit;
  final int? dayKey;

  @override
  ConsumerState<HabitCheckInSheet> createState() => _HabitCheckInSheetState();
}

class _HabitCheckInSheetState extends ConsumerState<HabitCheckInSheet> {
  late final TextEditingController _noteController;
  bool _saving = false;

  /// Whether the note field has been seeded from the stored entry yet.
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  int get _dayKey => widget.dayKey ?? habitDayKey(ref.read(clockProvider)());

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Habit habit = widget.habit;
    final int key = _dayKey;
    final List<HabitLog> logs = ref.watch(habitLogsOfProvider(habit.id));
    HabitLog? entry;
    for (final HabitLog log in logs) {
      if (log.dayKey == key) {
        entry = log;
      }
    }
    // The note field is seeded from the stored entry once, then left alone: a
    // rebuild mid-typing must not overwrite what is being typed.
    if (!_seeded) {
      _seeded = true;
      _noteController.text = entry?.note ?? '';
    }
    final Set<int> doneDays = ref.watch(habitDoneDaysProvider)[habit.id] ??
        const <int>{};
    final int streak = habitStreak(
      habit: habit,
      doneDays: doneDays,
      today: ref.read(clockProvider)(),
    );
    final DateTime day = habitDayFromKey(key);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(habit.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(habit.name, style: text.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        <String>[
                          habit.scheduleLabel,
                          if (entry != null) AppStrings.habitCheckedIn,
                          if (streak > 0) AppStrings.habitStreakDays(streak),
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: AppStrings.habitHistory,
                  onPressed: () => unawaited(
                    showHabitHistorySheet(context, habit: habit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              AppDateFormatter.calendarDate(day, ref.read(clockProvider)()),
              style: text.labelLarge,
            ),
            const SizedBox(height: 8),
            if (habit.allowNote)
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: AppStrings.habitNoteLabel,
                  hintText: AppStrings.habitNoteHint,
                ),
              )
            else
              Text(
                AppStrings.habitAllowNoteHint,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                if (entry != null)
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => unawaited(_undo(habit)),
                    icon: const Icon(Icons.undo),
                    label: const Text(AppStrings.habitUndo),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : () => unawaited(_submit(habit)),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    entry == null
                        ? AppStrings.habitCheckIn
                        : AppStrings.save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(Habit habit) async {
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final int key = _dayKey;
    final String note = _noteController.text;

    try {
      await ref.read(habitLogsProvider.notifier).checkIn(
            habit.id,
            day: habitDayFromKey(key),
            note: habit.allowNote ? note : null,
          );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.habitCheckedInToast(habit.name))),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('${AppStrings.saveFailed}：$error')),
      );
    }
  }

  Future<void> _undo(Habit habit) async {
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(habitLogsProvider.notifier).undo(habit.id, _dayKey);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.habitUndoneToast(habit.name))),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('${AppStrings.saveFailed}：$error')),
      );
    }
  }
}
