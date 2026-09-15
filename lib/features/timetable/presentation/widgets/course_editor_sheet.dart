import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../settings/presentation/widgets/background_controls.dart';
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

/// The editor the phone's timetable opens, screen for screen.
///
/// Its shape is that app's, deliberately: 课程名 (必填), 教室 (非必填), 备注（如老师）,
/// 时段 with a count that adds and removes weekly meetings, 上课周数 picked as a
/// set, and 课程背景色. Someone who has filled in a timetable on this phone
/// before should be able to fill in this one without reading it.
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
  String? _backgroundImage;
  late double _backgroundDim;
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
    _backgroundImage = existing?.backgroundImage;
    _backgroundDim = existing?.backgroundDim ?? Course.defaultBackgroundDim;
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
          backgroundImage: _backgroundImage,
          backgroundDim: _backgroundDim,
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
            backgroundImage: _backgroundImage,
            clearBackgroundImage: _backgroundImage == null,
            backgroundDim: _backgroundDim,
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

  /// Picks a picture for this course alone, copied and cropped by the picker.
  ///
  /// The copy happens before the course is saved, so a dismissed editor leaves
  /// a file behind — the same bargain the app's own background makes, and the
  /// reason removal deletes the file rather than only forgetting its name.
  Future<void> _pickBackground() async {
    final String? path = await pickBackgroundImage(context);
    if (path == null) {
      return;
    }
    setState(() => _backgroundImage = path);
  }

  Future<void> _recropBackground() async {
    final String? current = _backgroundImage;
    if (current == null) {
      return;
    }
    final String? recropped = await recropBackgroundImage(context, current);
    if (recropped == null) {
      return;
    }
    setState(() => _backgroundImage = recropped);
  }

  /// Adds a weekly meeting, next to the last one.
  ///
  /// The count is how the phone asks for a second meeting, and it is a better
  /// question than a form row: "this course also happens on Thursday" is one
  /// fact, and the periods of a second meeting usually start near the first.
  void _addSlot() {
    final CourseSlot last = _slots.last;
    setState(() {
      _slots = <CourseSlot>[
        ..._slots,
        CourseSlot(
          weekday: last.weekday == DateTime.sunday
              ? DateTime.monday
              : last.weekday + 1,
          startPeriod: last.startPeriod,
          endPeriod: last.endPeriod,
        ),
      ];
    });
  }

  void _removeSlot() {
    if (_slots.length <= 1) {
      return;
    }
    setState(() => _slots = _slots.sublist(0, _slots.length - 1));
  }

  Future<void> _editSlot(int index) async {
    final CourseSlot? slot = await _pickSlot(
      context,
      slot: _slots[index],
      periodNumbers: <int>[
        for (final period in ref.read(periodsProvider)) period.index,
      ],
    );
    if (slot == null) {
      return;
    }
    setState(() => _slots = <CourseSlot>[
      for (int i = 0; i < _slots.length; i++) i == index ? slot : _slots[i],
    ]);
  }

  Future<void> _editWeeks() async {
    final Set<int>? weeks = await _pickWeeks(
      context,
      weeks: _weeks,
      totalWeeks: _totalWeeks,
    );
    if (weeks == null) {
      return;
    }
    setState(() => _weeks = weeks);
  }

  Future<void> _editColor() async {
    final _ColorChoice? choice = await _pickColor(context, color: _color);
    if (choice == null) {
      return;
    }
    setState(() => _color = choice.argb);
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
    final CourseClash? clash = _currentClash();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // Capped, scrollable, and with its buttons *outside* the scrolling part.
      //
      // A course name pasted out of a school's system is a paragraph, and so are
      // its room and note; a form whose 完成 button scrolls with that text is a
      // form whose button ends up drawn over it. The row below never moves.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
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
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameController,
                autofocus: widget.existing == null,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: AppStrings.courseNameLabel,
                  hintText: AppStrings.courseNameHint,
                  helperText: AppStrings.courseRequired,
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty)
                        ? AppStrings.courseNameRequired
                        : null,
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _roomController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: AppStrings.courseRoomLabel,
                  hintText: AppStrings.courseRoomHint,
                  helperText: AppStrings.courseOptional,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _noteController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: AppStrings.courseNoteLabel,
                ),
              ),

              // --- 时段: how many weekly meetings, and when each one is --------
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  _Label(AppStrings.courseSlotsLabel),
                  const Spacer(),
                  IconButton(
                    tooltip: AppStrings.courseRemoveSlot,
                    onPressed: _slots.length <= 1 ? null : _removeSlot,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('${_slots.length}', style: text.titleMedium),
                  IconButton(
                    tooltip: AppStrings.courseAddSlot,
                    onPressed: _addSlot,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              for (int index = 0; index < _slots.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: Text(AppStrings.courseSlotCount(index + 1)),
                  subtitle: Text(_slots[index].label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(_editSlot(index)),
                ),

              // --- 上课周数 ----------------------------------------------------
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range_outlined),
                title: const Text(AppStrings.courseWeeksLabel),
                subtitle: Text(
                  _weeks.isEmpty
                      ? AppStrings.courseWeeksRequired
                      : _weeksLabel(),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(_editWeeks()),
              ),

              // --- 课程背景色 --------------------------------------------------
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _ColorDotPreview(argb: _color),
                title: const Text(AppStrings.courseColorLabel),
                subtitle: Text(_colorLabel(colors)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(_editColor()),
              ),

              // --- 课程背景 ----------------------------------------------------
              const SizedBox(height: 6),
              _Label(AppStrings.courseBackgroundLabel),
              const SizedBox(height: 2),
              Text(
                AppStrings.courseBackgroundHint,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              BackgroundControls(
                imagePath: _backgroundImage,
                dim: _backgroundDim,
                onPick: () => unawaited(_pickBackground()),
                onRecrop: () => unawaited(_recropBackground()),
                onRemove: () => setState(() => _backgroundImage = null),
                onDimChanged: (double value) =>
                    setState(() => _backgroundDim = value),
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
                    ],
                  ),
                ),
              ),
            ),
            _EditorActions(
              saving: _saving,
              canDelete: widget.existing != null,
              onDelete: () => unawaited(_confirmDelete()),
              onCancel: () => Navigator.of(context).pop(),
              onSubmit: () => unawaited(_submit()),
            ),
          ],
        ),
      ),
    );
  }

  /// `每周`, or the weeks it names.
  String _weeksLabel() => _draftCourse().weeksLabel(_totalWeeks);

  String _colorLabel(ColorScheme colors) {
    final int? argb = _color;
    if (argb == null) {
      return AppStrings.courseColorNone;
    }
    for (final AppPaletteColor option in courseColors(colors)) {
      if (option.argb == argb) {
        return option.label;
      }
    }
    return AppStrings.courseColorLabel;
  }

  /// The course as it currently reads, so the summary lines and the clash check
  /// are about what is on screen rather than about what was loaded.
  Course _draftCourse() {
    final Course? existing = widget.existing;
    return Course(
      id: existing?.id ?? '__draft__',
      name: _nameController.text.isEmpty ? '新课程' : _nameController.text,
      slots: _slots,
      weeks: _weeks,
      createdAt: existing?.createdAt ?? DateTime(2000),
    );
  }

  /// The first collision this course would have as it is currently written.
  CourseClash? _currentClash() {
    final Timetable? timetable = _timetable;
    if (timetable == null || _weeks.isEmpty || _slots.isEmpty) {
      return null;
    }
    return timetable.clashWith(_draftCourse());
  }
}

/// The editor's buttons, pinned below the scrolling form.
///
/// Outside the scroll view on purpose: a course name pasted out of a school's
/// system is a paragraph, and a 完成 button that scrolls with it is a button that
/// ends up drawn over it.
class _EditorActions extends StatelessWidget {
  const _EditorActions({
    required this.saving,
    required this.canDelete,
    required this.onDelete,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool saving;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: <Widget>[
          if (canDelete)
            TextButton.icon(
              onPressed: saving ? null : onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text(AppStrings.actionDelete),
            ),
          const Spacer(),
          TextButton(
            onPressed: saving ? null : onCancel,
            child: const Text(AppStrings.cancel),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: saving ? null : onSubmit,
            icon: const Icon(Icons.check),
            label: const Text(AppStrings.done),
          ),
        ],
      ),
    );
  }
}

/// Picks one weekly meeting: which day, and which periods.
Future<CourseSlot?> _pickSlot(
  BuildContext context, {
  required CourseSlot slot,
  required List<int> periodNumbers,
}) {
  return showModalBottomSheet<CourseSlot>(
    context: context,
    builder: (_) => _SlotSheet(slot: slot, periodNumbers: periodNumbers),
  );
}

/// Three wheels: which day, which period it starts, which period it ends.
///
/// Wheels rather than a row of chips because a period is a number on a scale
/// rather than a set to choose from — every term has periods 1 to 9, in order,
/// and spinning to the ninth is how a thumb says "period 9" without reading
/// anything. The three are one gesture away from each other, which is what a
/// weekly meeting is: a day and a range.
class _SlotSheet extends StatefulWidget {
  const _SlotSheet({required this.slot, required this.periodNumbers});

  final CourseSlot slot;
  final List<int> periodNumbers;

  @override
  State<_SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends State<_SlotSheet> {
  late int _weekday = widget.slot.weekday;
  late int _start = widget.slot.startPeriod;
  late int _end = widget.slot.endPeriod;

  late final FixedExtentScrollController _weekdayWheel =
      FixedExtentScrollController(initialItem: _weekday - 1);
  late final FixedExtentScrollController _startWheel = FixedExtentScrollController(
    initialItem: _indexOfPeriod(_start),
  );
  late final FixedExtentScrollController _endWheel = FixedExtentScrollController(
    initialItem: _indexOfPeriod(_end) - _indexOfPeriod(_start),
  );

  int _indexOfPeriod(int period) {
    final int index = widget.periodNumbers.indexOf(period);
    return index < 0 ? 0 : index;
  }

  /// The periods [period] could end on: itself and everything after it.
  ///
  /// A range that ends before it begins is not a range, so the end wheel does
  /// not offer one — and when the start moves past the end, the end moves with
  /// it rather than being left behind.
  List<int> get _endChoices => <int>[
        for (final int period in widget.periodNumbers)
          if (period >= _start) period,
      ];

  void _onStartChanged(int index) {
    final int start = widget.periodNumbers[index];
    setState(() {
      _start = start;
      if (_end < start) {
        _end = start;
      }
    });
    // The end wheel's items changed underneath it, so it is re-pointed at the
    // period it is standing on rather than left at a stale offset.
    _endWheel.jumpToItem(_endChoices.indexOf(_end).clamp(0, _endChoices.length - 1));
  }

  @override
  void dispose() {
    _weekdayWheel.dispose();
    _startWheel.dispose();
    _endWheel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(AppStrings.cancel),
                ),
                Expanded(
                  child: Text(
                    AppStrings.courseSlotsLabel,
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    CourseSlot(
                      weekday: _weekday,
                      startPeriod: _start,
                      endPeriod: _end,
                    ),
                  ),
                  child: const Text(AppStrings.confirm),
                ),
              ],
            ),
          ),
          // The three columns are labelled above the wheels rather than beside
          // them: a wheel has no room for a label, and a label inside it would
          // scroll away with the values.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: <Widget>[
                Expanded(child: _WheelLabel(AppStrings.courseSlotWeekday)),
                Expanded(child: _WheelLabel(AppStrings.courseSlotFromLabel)),
                Expanded(child: _WheelLabel(AppStrings.courseSlotToLabel)),
              ],
            ),
          ),
          SizedBox(
            height: 216,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _weekdayWheel,
                    itemExtent: 40,
                    looping: true,
                    onSelectedItemChanged: (int index) =>
                        setState(() => _weekday = index + 1),
                    selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
                      background: Color(0x14000000),
                    ),
                    children: <Widget>[
                      for (int weekday = 1; weekday <= 7; weekday++)
                        _WheelItem('周${kCourseWeekdayNames[weekday - 1]}'),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _startWheel,
                    itemExtent: 40,
                    onSelectedItemChanged: _onStartChanged,
                    selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
                      background: Color(0x14000000),
                    ),
                    children: <Widget>[
                      for (final int period in widget.periodNumbers)
                        _WheelItem(AppStrings.periodLabel(period)),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _endWheel,
                    itemExtent: 40,
                    onSelectedItemChanged: (int index) =>
                        setState(() => _end = _endChoices[index]),
                    selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
                      background: Color(0x14000000),
                    ),
                    children: <Widget>[
                      for (final int period in _endChoices)
                        _WheelItem(AppStrings.periodLabel(period)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              CourseSlot(
                weekday: _weekday,
                startPeriod: _start,
                endPeriod: _end,
              ).label,
              style: text.titleMedium?.copyWith(color: colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelLabel extends StatelessWidget {
  const _WheelLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
}

class _WheelItem extends StatelessWidget {
  const _WheelItem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}


/// Picks the weeks a course runs, in the term's own numbering.
Future<Set<int>?> _pickWeeks(
  BuildContext context, {
  required Set<int> weeks,
  required int totalWeeks,
}) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WeekSheet(weeks: weeks, totalWeeks: totalWeeks),
  );
}

class _WeekSheet extends StatefulWidget {
  const _WeekSheet({required this.weeks, required this.totalWeeks});

  final Set<int> weeks;
  final int totalWeeks;

  @override
  State<_WeekSheet> createState() => _WeekSheetState();
}

class _WeekSheetState extends State<_WeekSheet> {
  late Set<int> _weeks = Set<int>.of(widget.weeks);

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(AppStrings.courseWeeksLabel, style: text.titleLarge),
            const SizedBox(height: 14),
            _WeekPicker(
              weeks: _weeks,
              totalWeeks: widget.totalWeeks,
              onChanged: (Set<int> weeks) => setState(() => _weeks = weeks),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(AppStrings.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_weeks),
                  child: const Text(AppStrings.confirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The colour a course is drawn in, or `null` for the palette by name.
class _ColorChoice {
  const _ColorChoice(this.argb);

  final int? argb;
}

/// Picks the colour, which the phone calls 课程背景色.
Future<_ColorChoice?> _pickColor(BuildContext context, {required int? color}) {
  return showModalBottomSheet<_ColorChoice>(
    context: context,
    builder: (_) => _ColorSheet(color: color),
  );
}

class _ColorSheet extends StatelessWidget {
  const _ColorSheet({required this.color});

  final int? color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(AppStrings.courseColorLabel, style: text.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                for (final AppPaletteColor option in courseColors(colors))
                  _ColorDot(
                    argb: option.argb,
                    label: option.label,
                    selected: color == option.argb,
                    onTap: () =>
                        Navigator.of(context).pop(_ColorChoice(option.argb)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(const _ColorChoice(null)),
                icon: const Icon(Icons.format_color_reset_outlined),
                label: const Text(AppStrings.courseColorNone),
              ),
            ),
          ],
        ),
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

/// The colour as the row's leading dot, or an empty ring when none is set.
class _ColorDotPreview extends StatelessWidget {
  const _ColorDotPreview({required this.argb});

  final int? argb;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: argb == null ? null : Color(argb!),
        shape: BoxShape.circle,
        border: Border.all(color: colors.outlineVariant, width: 2),
      ),
      child: argb == null
          ? Icon(Icons.format_color_reset_outlined, size: 18, color: colors.outline)
          : null,
    );
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
