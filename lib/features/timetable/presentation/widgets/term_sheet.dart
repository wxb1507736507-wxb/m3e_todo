import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/utils/calendar.dart';
import '../../../media/presentation/image_crop_page.dart';
import '../../../settings/domain/app_settings.dart';
import '../../../settings/presentation/settings_controller.dart';
import '../../domain/entities/period_time.dart';
import '../../domain/entities/term.dart';
import '../../domain/entities/timetable.dart';
import '../providers/timetable_providers.dart';

/// Opens the term settings: the term's name and length, and the day's periods.
///
/// One sheet for both because they are the same decision seen twice — how the
/// timetable is laid out — and because changing the periods changes what a
/// course's "periods 3 to 4" means.
Future<void> showTermSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const TermSheet(),
  );
}

class TermSheet extends ConsumerStatefulWidget {
  const TermSheet({super.key});

  @override
  ConsumerState<TermSheet> createState() => _TermSheetState();
}

class _TermSheetState extends ConsumerState<TermSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late DateTime _startMonday;
  late int _totalWeeks;
  late List<PeriodTime> _periods;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final Term term = ref.read(timetableProvider).value?.term ??
        Timetable.fresh(ref.read(clockProvider)()).term;
    _nameController = TextEditingController(text: term.name);
    _startMonday = term.startMonday;
    _totalWeeks = term.totalWeeks;
    _periods = List<PeriodTime>.of(term.periods);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startMonday,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      helpText: AppStrings.termStartLabel,
    );
    if (picked == null || !mounted) {
      return;
    }
    // The first Monday is what a week is counted from, so a Wednesday becomes
    // the Monday that starts that week.
    final DateTime monday = startOfDay(picked).subtract(Duration(days: picked.weekday - 1));
    setState(() => _startMonday = DateTime(monday.year, monday.month, monday.day));
  }

  Future<void> _retime(int index) async {
    final PeriodTime period = _periods[index];
    final TimeOfDay? start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: period.startMinutes ~/ 60,
        minute: period.startMinutes % 60,
      ),
      helpText: '${AppStrings.periodLabel(period.index)} 上课时间',
    );
    if (start == null || !mounted) {
      return;
    }
    final TimeOfDay? end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: period.endMinutes ~/ 60,
        minute: period.endMinutes % 60,
      ),
      helpText: '${AppStrings.periodLabel(period.index)} 下课时间',
    );
    if (end == null || !mounted) {
      return;
    }
    final int from = start.hour * 60 + start.minute;
    final int to = end.hour * 60 + end.minute;
    if (to <= from) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下课时间要晚于上课时间')),
      );
      return;
    }
    setState(() => _periods[index] = period.edited(startMinutes: from, endMinutes: to));
  }

  /// The timetable''s own background: pick, re-crop, remove, and how strongly the
  /// surface covers it.
  ///
  /// The same controls the app''s background has, and the same crop-and-copy
  /// step, because it is the same problem: a picture chosen here is copied into
  /// the app''s private directory and cropped to the screen, so nothing outside
  /// can delete it and no letterboxing appears.
  Future<void> _pickBackground() async {
    final CroppedImage? cropped = await pickAndCropImage(
      context,
      initialAspect: CropAspect.screen,
    );
    if (cropped == null) {
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .setTimetableBackgroundImage(cropped.path);
  }

  Future<void> _recropBackground() async {
    final String? current = ref.read(settingsProvider).timetableBackgroundImage;
    if (current == null) {
      return;
    }
    final CroppedImage? cropped = await cropImage(
      context,
      sourcePath: current,
      initialAspect: CropAspect.screen,
    );
    if (cropped == null) {
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .setTimetableBackgroundImage(cropped.path);
  }

  Widget _buildBackgroundControls(BuildContext context) {
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final String? path = settings.timetableBackgroundImage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(AppStrings.timetableBackgroundLabel, style: text.labelLarge),
        const SizedBox(height: 2),
        Text(
          AppStrings.timetableBackgroundHint,
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (path != null)
          ClipRRect(
            borderRadius: AppShapes.radius(AppShapes.small),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: Image.file(File(path), fit: BoxFit.cover),
            ),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: () => unawaited(_pickBackground()),
              icon: const Icon(Icons.image_outlined),
              label: Text(
                path == null
                    ? AppStrings.appBackgroundPick
                    : AppStrings.appBackgroundChange,
              ),
            ),
            if (path != null) ...<Widget>[
              TextButton.icon(
                onPressed: () => unawaited(_recropBackground()),
                icon: const Icon(Icons.crop),
                label: const Text(AppStrings.cropBackgroundImage),
              ),
              TextButton.icon(
                onPressed: () => unawaited(
                  controller.setTimetableBackgroundImage(null),
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text(AppStrings.appBackgroundRemove),
              ),
            ],
          ],
        ),
        // The scrim only means something when there is a picture under it, and
        // it is the control that keeps course names readable over one.
        if (path != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(AppStrings.backgroundDimLabel, style: text.labelLarge),
          Slider(
            value: settings.timetableBackgroundDim,
            onChanged: controller.setTimetableBackgroundDim,
            label: AppStrings.backgroundDimValue(
              (settings.timetableBackgroundDim * 100).round(),
            ),
            divisions: 20,
          ),
          Text(
            AppStrings.backgroundDimValue(
              (settings.timetableBackgroundDim * 100).round(),
            ),
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    try {
      await ref.read(timetableProvider.notifier).setTerm(
            Term(
              name: _nameController.text.trim(),
              startMonday: _startMonday,
              totalWeeks: _totalWeeks,
              periods: _periods,
            ),
          );
      navigator.pop();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStrings.saveFailed}：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

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
              Text(AppStrings.timetableTermSettings, style: text.headlineSmall),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: AppStrings.termNameLabel,
                  hintText: AppStrings.termNameHint,
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty) ? '给学期起个名字' : null,
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined),
                title: const Text(AppStrings.termStartLabel),
                subtitle: Text(AppDateFormatter.calendarDate(_startMonday, _startMonday)),
                onTap: _pickStart,
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      AppStrings.termWeeksLabel,
                      style: text.bodyLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _totalWeeks <= 1
                        ? null
                        : () => setState(() => _totalWeeks--),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_totalWeeks 周', style: text.titleMedium),
                  IconButton(
                    onPressed: _totalWeeks >= 30
                        ? null
                        : () => setState(() => _totalWeeks++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(AppStrings.termPeriodsLabel, style: text.labelLarge),
              const SizedBox(height: 2),
              Text(
                AppStrings.termPeriodsHint,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              for (int index = 0; index < _periods.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(AppStrings.periodLabel(_periods[index].index)),
                  subtitle: Text(_periods[index].label),
                  trailing: const Icon(Icons.schedule, size: 18),
                  onTap: () => unawaited(_retime(index)),
                ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => setState(() {
                      final int next = _periods.isEmpty ? 1 : _periods.last.index + 1;
                      _periods.add(
                        PeriodTime(
                          index: next,
                          startMinutes: 8 * 60,
                          endMinutes: 8 * 60 + 45,
                        ),
                      );
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('加一节'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _periods.isEmpty
                        ? null
                        : () => setState(() => _periods.removeLast()),
                    icon: const Icon(Icons.remove),
                    label: const Text('减一节'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildBackgroundControls(context),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text(AppStrings.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => unawaited(_submit()),
                    icon: const Icon(Icons.check),
                    label: const Text(AppStrings.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
