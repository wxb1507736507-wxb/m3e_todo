import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/platform/app_platform.dart';
import '../../domain/timetable_import.dart';
import '../providers/timetable_providers.dart';

/// Reads a timetable out of a picture, shows what it found, and imports it.
///
/// Three steps, and the middle one is the point: the recogniser is good, not
/// right, and a term's worth of courses appearing in the timetable without the
/// user having seen them would be worse than typing them in. So the picture is
/// only ever a *proposal* — the sheet says what it read, the user unticks and
/// renames, and nothing is written until they say 导入.
Future<void> showCourseImportSheet(BuildContext context) async {
  final PickedAttachment? picked = await AppPlatform.pickAttachment('image');
  if (picked == null || !context.mounted) {
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CourseImportSheet(imagePath: picked.path),
  );
}

class CourseImportSheet extends ConsumerStatefulWidget {
  const CourseImportSheet({required this.imagePath, super.key});

  /// The picture to read, already copied into the app's own directory.
  final String imagePath;

  @override
  ConsumerState<CourseImportSheet> createState() => _CourseImportSheetState();
}

class _CourseImportSheetState extends ConsumerState<CourseImportSheet> {
  List<ImportedCourse>? _courses;
  int _skippedLines = 0;
  String? _error;
  bool _busy = true;
  bool _importing = false;

  /// The courses the user has kept, by the name they were read as.
  final Set<String> _dropped = <String>{};

  /// Names the user corrected, keyed by the name as it was read.
  final Map<String, String> _renamed = <String, String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      // Through the provider rather than straight to the platform: this is the
      // one step no test machine can perform, and the rest of the feature is
      // worth testing.
      final List<Map<String, Object?>> lines =
          await ref.read(textRecognitionProvider)(widget.imagePath);
      if (!mounted) {
        return;
      }
      final ImportedTimetable read = readTimetable(
        <TextBox>[
          for (final Map<String, Object?> line in lines)
            TextBox(
              text: line['text'] as String? ?? '',
              left: (line['l'] as num?)?.toDouble() ?? 0,
              top: (line['t'] as num?)?.toDouble() ?? 0,
              right: (line['r'] as num?)?.toDouble() ?? 0,
              bottom: (line['b'] as num?)?.toDouble() ?? 0,
            ),
        ],
        periodCount: ref.read(periodsProvider).length,
      );
      if (kDebugMode) {
        // Debug-only, and the only place it can be seen: what the recogniser
        // actually answered is the one part of 识图导课 a test machine cannot
        // produce, so when a real photo reads wrongly this is where the reading
        // — as opposed to the arithmetic on it — can be looked at.
        debugPrint('course-import-ocr: ${jsonEncode(lines)}');
        debugPrint(
          'course-import-read: ${read.courses} skipped=${read.skippedLines}',
        );
      }
      setState(() {
        _courses = read.courses;
        _skippedLines = read.skippedLines;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  List<ImportedCourse> get _kept => <ImportedCourse>[
        for (final ImportedCourse course in _courses ?? const <ImportedCourse>[])
          if (!_dropped.contains(course.name)) _renamedCourse(course),
      ];

  ImportedCourse _renamedCourse(ImportedCourse course) {
    final String? name = _renamed[course.name];
    return name == null ? course : course.edited(name: name);
  }

  Future<void> _rename(ImportedCourse course) async {
    final TextEditingController controller =
        TextEditingController(text: _renamedCourse(course).name);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text(AppStrings.courseImportRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: AppStrings.courseNameLabel,
          ),
          onSubmitted: (String value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text(AppStrings.done),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) {
      return;
    }
    setState(() => _renamed[course.name] = name);
  }

  Future<void> _import() async {
    final List<ImportedCourse> kept = _kept;
    if (kept.isEmpty || _importing) {
      return;
    }
    setState(() => _importing = true);
    final NavigatorState navigator = Navigator.of(context);
    final ({int imported, int alreadyThere}) result =
        await ref.read(timetableProvider.notifier).importCourses(kept);
    if (!mounted) {
      return;
    }
    navigator.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.alreadyThere == 0
              ? AppStrings.courseImportDone(result.imported)
              : AppStrings.courseImportDoneSome(result.imported, result.alreadyThere),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(AppStrings.courseImportTitle, style: text.headlineSmall),
              const SizedBox(height: 8),
              if (_busy) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(AppStrings.courseImportWorking, style: text.bodyLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.courseImportTakeLong,
                  style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ] else if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '${AppStrings.courseImportFailed}：$_error',
                  style: text.bodyMedium?.copyWith(color: colors.error),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(AppStrings.done),
                  ),
                ),
              ] else if (_courses == null || _courses!.isEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  AppStrings.courseImportEmpty,
                  style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(AppStrings.done),
                  ),
                ),
              ] else ...<Widget>[
                Text(
                  AppStrings.courseImportFound(_courses!.length),
                  style: text.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  AppStrings.courseImportReviewHint,
                  style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
                if (_skippedLines > 0)
                  Text(
                    AppStrings.courseImportSkipped(_skippedLines),
                    style: text.bodySmall?.copyWith(color: colors.outline),
                  ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.courseImportWeeksHint,
                  style: text.bodySmall?.copyWith(color: colors.outline),
                ),
                const SizedBox(height: 8),
                for (final ImportedCourse course in _courses!)
                  _ImportRow(
                    course: course,
                    name: _renamedCourse(course).name,
                    kept: !_dropped.contains(course.name),
                    onToggle: (bool keep) => setState(() {
                      if (keep) {
                        _dropped.remove(course.name);
                      } else {
                        _dropped.add(course.name);
                      }
                    }),
                    onRename: () => unawaited(_rename(course)),
                  ),
                const SizedBox(height: 12),
                Text(
                  '${AppStrings.courseImportFound(_courses!.length)} · '
                  '${AppStrings.courseWeeksLabel}：${AppStrings.courseWeeksAll}',
                  style: text.bodySmall?.copyWith(color: colors.outline),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    const Spacer(),
                    TextButton(
                      onPressed:
                          _importing ? null : () => Navigator.of(context).pop(),
                      child: const Text(AppStrings.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _importing || _kept.isEmpty
                          ? null
                          : () => unawaited(_import()),
                      icon: const Icon(Icons.download_done_outlined),
                      label: Text(AppStrings.courseImportAction(_kept.length)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportRow extends StatelessWidget {
  const _ImportRow({
    required this.course,
    required this.name,
    required this.kept,
    required this.onToggle,
    required this.onRename,
  });

  final ImportedCourse course;
  final String name;
  final bool kept;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String meta = <String>[
      if (course.room != null) course.room!,
      if (course.note != null) course.note!,
      course.slotsLabel,
    ].join(' · ');

    return CheckboxListTile(
      value: kept,
      onChanged: (bool? value) => onToggle(value ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        name,
        style: text.titleSmall?.copyWith(
          decoration: kept ? null : TextDecoration.lineThrough,
          color: kept ? null : colors.outline,
        ),
      ),
      subtitle: Text(meta, style: text.bodySmall),
      secondary: IconButton(
        tooltip: AppStrings.courseImportRename,
        onPressed: onRename,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }
}
