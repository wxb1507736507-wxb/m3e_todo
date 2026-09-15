import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_palette.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/timetable.dart';
import '../providers/timetable_providers.dart';

/// Opens the course editor: a new course, or an existing one to change.
///
/// Returns the course that was saved, or `null` when the sheet was dismissed.
Future<Course?> showCourseEditorSheet(
  BuildContext context, {
  Course? existing,
  int? weekday,
  int? period,
}) {
  return showModalBottomSheet<Course>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CourseEditorSheet(
      existing: existing,
      weekday: weekday,
      period: period,
    ),
  );
}

/// The colours a course can be marked with.
///
/// The same eight the folders use, because a colour here is a label rather than
/// a design decision — and eight is what a timetable needs to keep a term's
/// courses apart at a glance.
List<AppPaletteColor> courseColors(ColorScheme colors) => <AppPaletteColor>[
      AppPaletteColor(colors.primary.toARGB32(), '主色'),
      AppPaletteColor(0xFFE53935, '红'),
      AppPaletteColor(0xFFFB8C00, '橙'),
      AppPaletteColor(0xFFFDD835, '黄'),
      AppPaletteColor(0xFF43A047, '绿'),
      AppPaletteColor(0xFF00897B, '青绿'),
      AppPaletteColor(0xFF1E88E5, '蓝'),
      AppPaletteColor(0xFF8E24AA, '紫'),
    ];

class CourseEditorSheet extends ConsumerStatefulWidget {
  const CourseEditorSheet({
    this.existing,
    this.weekday,
    this.period,
    super.key,
  });

  final Course? existing;

  /// Where the new course starts, when the editor was opened from a cell.
  final int? weekday;
  final int? period;

  @override
  ConsumerState<CourseEditorSheet> createState() => _CourseEditorSheetState();
}

class _CourseEditorSheetState extends ConsumerState<CourseEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _roomController;
  late final TextEditingController _noteController;
  late List<CourseSlot> _slots;
  late Set<int> _weeks;
  late int? _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final Course? existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _roomController = TextEditingController(text: existing?.room ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _slots = existing == null
        ? <CourseSlot>[
            CourseSlot(
              weekday: widget.weekday ?? DateTime.monday,
              startPeriod: widget.period ?? 1,
              endPeriod: widget.period ?? 1,
            ),
          ]
        : List<CourseSlot>.of(existing.slots);
    _weeks = existing == null
        ? <int>{for (int week = 1; week <= 18; week++) week}
        : Set<int>.of(existing.weeks);
    _color = existing?.color;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Timetable? get _timetable => ref.read(timetableProvider).value;

  int get _totalWeeks => _timetable?.term.totalWeeks ?? 18;

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_slots.isEmpty) {
      _say(AppStrings.courseSlotsRequired);
      return;
    }
    if (_weeks.isEmpty) {
      _say(AppStrings.courseWeeksRequired);
      return;
    }
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    final TimetableController controller = ref.read(timetableProvider.notifier);
    final Course? existing = widget.existing;

    try {
      final Course saved;
      if (existing == null) {
        saved = await controller.addCourse(
          name: _nameController.text,
          slots: _slots,
          weeks: _weeks,
          room: _roomController.text,
          note: _noteController.text,
          color: _color,
        );
      } else {
        await controller.editCourse(
          existing.id,
          (Course current) => current.edited(
            name: _nameController.text,
            slots: _slots,
            weeks: _weeks,
            room: _roomController.text,
            clearRoom: _roomController.text.trim().isEmpty,
            note: _noteController.text,
            clearNote: _noteController.text.trim().isEmpty,
            color: _color,
            clearColor: _color == null,
          ),
        );
        saved = existing.edited(name: _nameController.text);
      }
      navigator.pop(saved);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      _say('${AppStrings.saveFailed}：$error');
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete() async {
    final Course? existing = widget.existing;
    if (existing == null) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text(AppStrings.courseDeleteTitle),
        content: Text(AppStrings.courseDeleteBody(existing.name)),
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
    await ref.read(timetableProvider.notifier).removeCourse(existing.id);
    navigator.pop();
    _say(AppStrings.courseDeleted(existing.name));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final List<int> periodNumbers = <int>[
      for (final period in ref.watch(periodsProvider)) period.index,
    ];
    final CourseClash? clash = _currentClash();

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
                    ? AppStrings.courseNew
                    : AppStrings.courseEdit,
                style: text.headlineSmall,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameController,
                autofocus: widget.existing == null,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: AppStrings.courseNameLabel,
                  hintText: AppStrings.courseNameHint,
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty)
                        ? AppStrings.courseNameRequired
                        : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _roomController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: AppStrings.courseRoomLabel,
                        hintText: AppStrings.courseRoomHint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _noteController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: AppStrings.courseNoteLabel,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _Label(AppStrings.courseSlotsLabel),
              const SizedBox(height: 6),
              for (int index = 0; index < _slots.length; index++)
                _SlotRow(
                  slot: _slots[index],
                  periodNumbers: periodNumbers,
                  canRemove: _slots.length > 1,
                  onChanged: (CourseSlot slot) =>
                      setState(() => _slots[index] = slot),
                  onRemove: () => setState(() => _slots.removeAt(index)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _slots.add(
                      CourseSlot(
                        weekday: _slots.last.weekday,
                        startPeriod: _slots.last.endPeriod + 1,
                        endPeriod: _slots.last.endPeriod + 1,
                      ),
                    );
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text(AppStrings.courseAddSlot),
                ),
              ),
              const SizedBox(height: 8),
              _Label(AppStrings.courseWeeksLabel),
              const SizedBox(height: 6),
              _WeekPicker(
                weeks: _weeks,
                totalWeeks: _totalWeeks,
                onChanged: (Set<int> weeks) => setState(() => _weeks = weeks),
              ),
              const SizedBox(height: 14),
              _Label(AppStrings.courseColorLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final AppPaletteColor option in courseColors(colors))
                    _ColorDot(
                      argb: option.argb,
                      label: option.label,
                      selected: _color == option.argb,
                      onTap: () => setState(() {
                        _color = _color == option.argb ? null : option.argb;
                      }),
                    ),
                ],
              ),
              // Said before saving, not after: a clash is invisible on the grid
              // until the term has started, which is far too late to notice.
              if (clash != null) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded, color: colors.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppStrings.courseClash(
                          clash.first.id == widget.existing?.id
                              ? clash.second.name
                              : clash.first.name,
                          clash.label,
                        ),
                        style: text.bodySmall?.copyWith(color: colors.error),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
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
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
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

  /// The first collision this course would have as it is currently written.
  CourseClash? _currentClash() {
    final Timetable? timetable = _timetable;
    if (timetable == null || _weeks.isEmpty || _slots.isEmpty) {
      return null;
    }
    final Course candidate = Course(
      id: widget.existing?.id ?? '__draft__',
      name: _nameController.text.isEmpty ? '新课程' : _nameController.text,
      slots: _slots,
      weeks: _weeks,
      createdAt: DateTime(2000),
    );
    return timetable.clashWith(candidate);
  }
}

/// One weekly meeting: which day, and which periods.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.periodNumbers,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final CourseSlot slot;
  final List<int> periodNumbers;
  final bool canRemove;
  final ValueChanged<CourseSlot> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: slot.weekday,
              decoration: const InputDecoration(
                labelText: AppStrings.courseSlotWeekday,
                isDense: true,
              ),
              items: <DropdownMenuItem<int>>[
                for (int weekday = 1; weekday <= 7; weekday++)
                  DropdownMenuItem<int>(
                    value: weekday,
                    child: Text('周${kCourseWeekdayNames[weekday - 1]}'),
                  ),
              ],
              onChanged: (int? value) =>
                  value == null ? null : onChanged(slot.edited(weekday: value)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<int>(
              initialValue: slot.startPeriod,
              decoration: const InputDecoration(
                labelText: '从',
                isDense: true,
              ),
              items: <DropdownMenuItem<int>>[
                for (final int period in periodNumbers)
                  DropdownMenuItem<int>(
                    value: period,
                    child: Text(AppStrings.periodLabel(period)),
                  ),
              ],
              onChanged: (int? value) {
                if (value == null) {
                  return;
                }
                onChanged(
                  slot.edited(
                    startPeriod: value,
                    // The end follows the start rather than being left behind
                    // it: a range that ends before it begins is not a range.
                    endPeriod: value > slot.endPeriod ? value : slot.endPeriod,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<int>(
              initialValue: slot.endPeriod,
              decoration: const InputDecoration(
                labelText: '到',
                isDense: true,
              ),
              items: <DropdownMenuItem<int>>[
                for (final int period in periodNumbers)
                  if (period >= slot.startPeriod)
                    DropdownMenuItem<int>(
                      value: period,
                      child: Text('第$period节'),
                    ),
              ],
              onChanged: (int? value) =>
                  value == null ? null : onChanged(slot.edited(endPeriod: value)),
            ),
          ),
          IconButton(
            onPressed: canRemove ? onRemove : null,
            icon: const Icon(Icons.close),
            tooltip: AppStrings.courseRemoveSlot,
          ),
        ],
      ),
    );
  }
}

/// The weeks a course runs, picked rather than typed.
///
/// A grid of the term's weeks with the shortcuts a term actually needs — every
/// week, odd, even, the halves — because "1, 3, 5, 7, 17, 18" is a pattern
/// somebody has to be able to write without counting on their fingers.
class _WeekPicker extends StatelessWidget {
  const _WeekPicker({
    required this.weeks,
    required this.totalWeeks,
    required this.onChanged,
  });

  final Set<int> weeks;
  final int totalWeeks;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final int half = (totalWeeks / 2).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            ActionChip(
              label: const Text(AppStrings.courseWeeksAll),
              onPressed: () => onChanged(<int>{
                for (int week = 1; week <= totalWeeks; week++) week,
              }),
            ),
            ActionChip(
              label: const Text(AppStrings.courseWeeksOdd),
              onPressed: () => onChanged(<int>{
                for (int week = 1; week <= totalWeeks; week += 2) week,
              }),
            ),
            ActionChip(
              label: const Text(AppStrings.courseWeeksEven),
              onPressed: () => onChanged(<int>{
                for (int week = 2; week <= totalWeeks; week += 2) week,
              }),
            ),
            ActionChip(
              label: const Text(AppStrings.courseWeeksFirstHalf),
              onPressed: () => onChanged(<int>{
                for (int week = 1; week <= half; week++) week,
              }),
            ),
            ActionChip(
              label: const Text(AppStrings.courseWeeksSecondHalf),
              onPressed: () => onChanged(<int>{
                for (int week = half + 1; week <= totalWeeks; week++) week,
              }),
            ),
            ActionChip(
              label: const Text(AppStrings.courseWeeksClear),
              onPressed: () => onChanged(<int>{}),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (int week = 1; week <= totalWeeks; week++)
              Semantics(
                button: true,
                selected: weeks.contains(week),
                label: '第$week周',
                child: InkWell(
                  onTap: () => onChanged(<int>{
                    ...weeks.contains(week)
                        ? (weeks.toSet()..remove(week))
                        : (weeks.toSet()..add(week)),
                  }),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: weeks.contains(week)
                          ? colors.primary
                          : colors.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$week',
                      style: text.labelSmall?.copyWith(
                        color: weeks.contains(week)
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          (weeks.toList()..sort()).isEmpty
              ? AppStrings.courseWeeksRequired
              : _summary(),
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  String _summary() {
    final List<int> sorted = weeks.toList()..sort();
    return '已选 ${sorted.length} 周：${sorted.join(', ')}';
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.argb,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int argb;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Color(argb),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colors.onSurface : colors.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge,
      );
}

