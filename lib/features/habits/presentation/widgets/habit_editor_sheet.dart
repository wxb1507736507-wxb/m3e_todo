import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../domain/entities/habit.dart';
import '../habit_permissions.dart';
import '../providers/habit_providers.dart';

/// Opens the habit editor: name, icon, which days, and whether it reminds.
///
/// Returns the habit that was saved, or `null` when the sheet was dismissed.
Future<Habit?> showHabitEditorSheet(
  BuildContext context, {
  Habit? existing,
}) {
  return showModalBottomSheet<Habit>(
    context: context,
    isScrollControlled: true,
    builder: (_) => HabitEditorSheet(existing: existing),
  );
}

class HabitEditorSheet extends ConsumerStatefulWidget {
  const HabitEditorSheet({this.existing, super.key});

  final Habit? existing;

  @override
  ConsumerState<HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends ConsumerState<HabitEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String _emoji;
  late int _days;

  /// Set when the habit counts days instead of following the week; `null` means
  /// the weekday chips are the schedule.
  late int? _intervalDays;
  late int? _reminderMinutes;
  late bool _allowNote;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final Habit? existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _emoji = existing?.emoji ?? kHabitEmoji.first;
    _days = existing?.days ?? kHabitEveryDay;
    _intervalDays = existing?.intervalDays;
    _reminderMinutes = existing?.reminderMinutes;
    _allowNote = existing?.allowNote ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final int? current = _reminderMinutes;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 8, minute: 0)
          : TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: AppStrings.habitReminderPick,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _reminderMinutes = picked.hour * 60 + picked.minute);
  }

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_intervalDays == null && _days & kHabitEveryDay == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.habitDaysRequired)),
      );
      return;
    }
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final HabitsController controller = ref.read(habitsProvider.notifier);
    final Habit? existing = widget.existing;

    try {
      final Habit saved;
      if (existing == null) {
        saved = await controller.add(
          name: _nameController.text,
          emoji: _emoji,
          days: _days,
          intervalDays: _intervalDays,
          reminderMinutes: _reminderMinutes,
          allowNote: _allowNote,
        );
      } else {
        await controller.edit(
          existing.id,
          (Habit current) => current.edited(
            name: _nameController.text,
            emoji: _emoji,
            days: _days,
            intervalDays: _intervalDays,
            clearInterval: _intervalDays == null,
            reminderMinutes: _reminderMinutes,
            clearReminder: _reminderMinutes == null,
            allowNote: _allowNote,
          ),
        );
        saved = existing.edited(
          name: _nameController.text,
          emoji: _emoji,
          days: _days,
          intervalDays: _intervalDays,
          clearInterval: _intervalDays == null,
          reminderMinutes: _reminderMinutes,
          clearReminder: _reminderMinutes == null,
          allowNote: _allowNote,
        );
      }
      navigator.pop(saved);
      // Asked *after* the sheet closes, and with the messenger captured before
      // it did: turning on a reminder is the one moment the permission request
      // makes sense, and a dialog behind a closing sheet is a dialog nobody
      // reads.
      if (saved.reminds) {
        unawaited(
          ref.read(habitPermissionsProvider).ensureReminderDelivery(messenger),
        );
      }
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

  Future<void> _confirmDelete() async {
    final Habit? existing = widget.existing;
    if (existing == null) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text(AppStrings.habitDeleteTitle),
        content: Text(AppStrings.habitDeleteBody(existing.name)),
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
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(habitsProvider.notifier).remove(existing.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('${AppStrings.habitDeleted}「${existing.name}」')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final int? minutes = _reminderMinutes;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.existing == null
                    ? AppStrings.habitNew
                    : AppStrings.habitEdit,
                style: text.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                autofocus: widget.existing == null,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: AppStrings.habitNameLabel,
                  hintText: AppStrings.habitNameHint,
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty)
                        ? AppStrings.habitNameRequired
                        : null,
                onFieldSubmitted: (_) => unawaited(_submit()),
              ),
              const SizedBox(height: 18),
              _Label(AppStrings.habitIconLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String emoji in kHabitEmoji)
                    _EmojiChoice(
                      emoji: emoji,
                      selected: emoji == _emoji,
                      onTap: () => setState(() => _emoji = emoji),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _Label(AppStrings.habitDaysLabel),
              const SizedBox(height: 8),
              // Two ways to say when, and they are alternatives rather than
              // settings that add up: a habit follows the week or it follows a
              // count of days, never both.
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: false,
                    label: Text(AppStrings.habitScheduleWeekly),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text(AppStrings.habitScheduleInterval),
                  ),
                ],
                selected: <bool>{_intervalDays != null},
                onSelectionChanged: (Set<bool> selection) => setState(() {
                  if (selection.contains(true)) {
                    _intervalDays = _intervalDays ?? 2;
                  } else {
                    _intervalDays = null;
                  }
                }),
              ),
              const SizedBox(height: 10),
              if (_intervalDays == null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    // Three shortcuts first: almost every habit is one of them,
                    // and picking "每天" should not mean tapping seven chips.
                    _Shortcut(
                      label: AppStrings.habitEveryDay,
                      selected: _days == kHabitEveryDay,
                      onTap: () => setState(() => _days = kHabitEveryDay),
                    ),
                    _Shortcut(
                      label: AppStrings.habitWeekdays,
                      selected: _days == kHabitWeekdays,
                      onTap: () => setState(() => _days = kHabitWeekdays),
                    ),
                    _Shortcut(
                      label: AppStrings.habitWeekends,
                      selected: _days == kHabitWeekends,
                      onTap: () => setState(() => _days = kHabitWeekends),
                    ),
                    for (int bit = 0; bit < 7; bit++)
                      _DayChip(
                        label: kHabitWeekdayNames[bit],
                        selected: _days & (1 << bit) != 0,
                        onTap: () => setState(() {
                          _days = _days ^ (1 << bit);
                        }),
                      ),
                  ],
                )
              else
                Row(
                  children: <Widget>[
                    IconButton.filledTonal(
                      onPressed: _intervalDays! <= kHabitMinIntervalDays
                          ? null
                          : () => setState(() => _intervalDays = _intervalDays! - 1),
                      icon: const Icon(Icons.remove),
                      tooltip: AppStrings.habitIntervalLess,
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          AppStrings.habitEveryNDays(_intervalDays!),
                          style: text.titleMedium,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: _intervalDays! >= kHabitMaxIntervalDays
                          ? null
                          : () => setState(() => _intervalDays = _intervalDays! + 1),
                      icon: const Icon(Icons.add),
                      tooltip: AppStrings.habitIntervalMore,
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Text(
                _intervalDays == null
                    ? AppStrings.habitDaysHint
                    : AppStrings.habitIntervalHint(_intervalDays!),
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              // One row that is both the reminder's switch and its value: "不提醒"
              // and "08:00" are the same decision, and splitting them into a
              // switch plus a field would let the two disagree.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.alarm_outlined),
                title: const Text(AppStrings.habitReminderLabel),
                subtitle: Text(
                  minutes == null
                      ? AppStrings.habitReminderNone
                      : _timeLabel(minutes),
                ),
                trailing: minutes == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: AppStrings.habitReminderClear,
                        onPressed: () =>
                            setState(() => _reminderMinutes = null),
                      ),
                onTap: _pickTime,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowNote,
                onChanged: (bool value) => setState(() => _allowNote = value),
                title: const Text(AppStrings.habitAllowNote),
                subtitle: Text(
                  AppStrings.habitAllowNoteHint,
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  if (widget.existing != null)
                    TextButton.icon(
                      onPressed: _saving ? null : () => unawaited(_confirmDelete()),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text(AppStrings.actionDelete),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text(AppStrings.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => unawaited(_submit()),
                    icon: const Icon(Icons.check),
                    label: Text(
                      widget.existing == null
                          ? AppStrings.create
                          : AppStrings.save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _timeLabel(int minutes) {
    final String hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final String minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.labelLarge);
}

/// One emoji of the icon picker.
class _EmojiChoice extends StatelessWidget {
  const _EmojiChoice({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: emoji,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.radius(AppShapes.small),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerHigh,
            borderRadius: AppShapes.radius(AppShapes.small),
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}

/// One weekday, toggled on and off.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colors.primary : colors.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// 每天 / 工作日 / 周末.
class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
