import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/platform/app_platform.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../../../core/utils/calendar.dart';
import '../../../categories/presentation/widgets/category_picker.dart';
import '../../../todos/domain/entities/todo_attachment.dart';
import '../../../todos/presentation/providers/todo_providers.dart';
import '../../../todos/presentation/widgets/attachment_actions.dart';
import '../../domain/entities/note.dart';
import '../providers/note_providers.dart';

/// Opens the editor for a note.
///
/// Pass [existing] to edit one; omit it to write a new note for [date], which is
/// the day the calendar is showing. [initialCategoryId] files a new note under
/// the folder it was written from.
Future<void> showNoteSheet(
  BuildContext context, {
  Note? existing,
  required DateTime date,
  String? initialCategoryId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => NoteSheet(
      existing: existing,
      date: date,
      initialCategoryId: initialCategoryId,
    ),
  );
}

/// Writes and edits a note: words, a folder, and whatever was picked or recorded.
class NoteSheet extends ConsumerStatefulWidget {
  const NoteSheet({
    required this.date,
    this.existing,
    this.initialCategoryId,
    super.key,
  });

  final Note? existing;

  /// Which day the note belongs to. The calendar's selected day, so a note
  /// written while looking at the 3rd is filed under the 3rd.
  final DateTime date;

  /// The folder a *new* note should be filed under, when it was written from
  /// inside one. Ignored while editing: an existing note keeps its own folder
  /// unless the user changes it.
  final String? initialCategoryId;

  @override
  ConsumerState<NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<NoteSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _bodyController;
  late DateTime _date;
  String? _categoryId;
  List<TodoAttachment> _attachments = <TodoAttachment>[];
  bool _saving = false;

  /// Files this session created, so abandoning the sheet can delete exactly
  /// them — the same rule the todo editor follows.
  final Set<String> _newFiles = <String>{};
  final Set<String> _obsoleteFiles = <String>{};
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final Note? existing = widget.existing;
    _bodyController = TextEditingController(text: existing?.body ?? '');
    _date = existing?.date ?? startOfDay(widget.date);
    // A note can be written *inside* a folder, so the folder it was written
    // from is the sensible default rather than unfiled.
    _categoryId = existing?.categoryId ?? widget.initialCategoryId;
    _attachments = List<TodoAttachment>.of(
      existing?.attachments ?? const <TodoAttachment>[],
    );
  }

  @override
  void dispose() {
    if (!_saved) {
      _retire(abandoned: true);
    }
    _bodyController.dispose();
    super.dispose();
  }

  /// Deletes files that nothing will reference any more.
  ///
  /// [abandoned] is true while the sheet is being abandoned, when *every*
  /// file it added is unreferenced; after a successful save only the ones the
  /// edit dropped are.
  void _retire({required bool abandoned}) {
    for (final String path in abandoned ? _newFiles : _obsoleteFiles) {
      _deleteFile(path);
    }
    _obsoleteFiles.clear();
  }

  static void _deleteFile(String path) {
    unawaited(File(path).delete().catchError((Object _) => File(path)));
  }

  /// The note's day, said the way a person would: "今天", "明天", or the date.
  ///
  /// Not [AppDateFormatter.dayLabel], whose words are about deadlines — a note
  /// is never "due".
  String _dateLabel(DateTime now) {
    return switch (daysBetween(now, _date)) {
      0 => AppStrings.noteToday,
      1 => AppStrings.noteTomorrow,
      _ => AppDateFormatter.calendarDate(_date, now),
    };
  }

  Future<void> _pickDate() async {
    final DateTime now = ref.read(clockProvider)();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _date = startOfDay(picked));
    }
  }

  Future<void> _addAttachment(String kind) async {
    if (!attachmentsSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.attachmentUnsupported)),
      );
      return;
    }
    final TodoAttachment? attachment = kind == 'voice'
        ? await recordVoiceAttachment(context, ref)
        : await pickAndCreateAttachment(context, ref, kind);
    if (attachment == null || !mounted) {
      return;
    }
    _newFiles.add(attachment.path);
    setState(
      () => _attachments = <TodoAttachment>[..._attachments, attachment],
    );
  }

  void _removeAttachment(TodoAttachment attachment) {
    if (!_newFiles.remove(attachment.path)) {
      _obsoleteFiles.add(attachment.path);
    } else {
      _deleteFile(attachment.path);
    }
    setState(() {
      _attachments = <TodoAttachment>[
        for (final TodoAttachment a in _attachments)
          if (a.id != attachment.id) a,
      ];
    });
  }

  Future<void> _openAttachment(TodoAttachment attachment) async {
    final bool opened =
        await AppPlatform.openAttachment(attachment.path, attachment.mime);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.attachmentOpenFailed)),
      );
    }
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }
    if (_bodyController.text.trim().isEmpty && _attachments.isEmpty) {
      // A note with nothing in it is not worth saving; say why rather than
      // silently doing nothing.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.noteEmpty)),
      );
      return;
    }
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NotesController controller = ref.read(notesProvider.notifier);

    try {
      final Note? existing = widget.existing;
      if (existing == null) {
        await controller.add(
          date: _date,
          body: _bodyController.text,
          categoryId: _categoryId,
          attachments: _attachments,
        );
      } else {
        await controller.edit(
          existing.id,
          date: _date,
          body: _bodyController.text,
          categoryId: _categoryId,
          attachments: _attachments,
        );
      }
      // Marked before popping: dispose runs during the pop and must not delete
      // files the stored note now references.
      _saved = true;
      _retire(abandoned: false);
      navigator.pop();
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

  Future<void> _delete() async {
    final Note? existing = widget.existing;
    if (existing == null) {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    final List<String> orphaned =
        await ref.read(notesProvider.notifier).remove(existing.id);
    // The note is gone, so nothing references its files any more: the controller
    // hands back the paths and this is where they are deleted. `_newFiles` is
    // cleared first so dispose() does not try to delete them a second time.
    _newFiles.clear();
    _saved = true;
    for (final String path in orphaned) {
      _deleteFile(path);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime now = ref.read(clockProvider)();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.existing == null
                            ? AppStrings.noteNew
                            : AppStrings.noteEdit,
                        style: text.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _dateLabel(now),
                              style: text.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => unawaited(_pickDate()),
                            icon: const Icon(Icons.event_outlined, size: 18),
                            label: const Text(AppStrings.noteChangeDate),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _bodyController,
                        minLines: 5,
                        maxLines: 12,
                        autofocus: widget.existing == null,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          hintText: AppStrings.noteBodyHint,
                          border: InputBorder.none,
                        ),
                      ),
                      // Always shown, because it is also how a folder gets
                      // made: the moment you want a new one is the moment you
                      // are filing something.
                      const Divider(),
                      CategoryPicker(
                        value: _categoryId,
                        onChanged: (String? id) =>
                            setState(() => _categoryId = id),
                      ),
                      const Divider(),
                      Text(AppStrings.attachmentsLabel, style: text.labelLarge),
                      const SizedBox(height: 8),
                      if (_attachments.isNotEmpty) ...<Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final TodoAttachment attachment in _attachments)
                              AttachmentChip(
                                attachment: attachment,
                                onOpen: () =>
                                    unawaited(_openAttachment(attachment)),
                                onRemove: () => _removeAttachment(attachment),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      MenuAnchor(
                        menuChildren: <Widget>[
                          _attachItem('image', Icons.image_outlined,
                              AppStrings.attachImage),
                          _attachItem('video', Icons.videocam_outlined,
                              AppStrings.attachVideo),
                          _attachItem('document', Icons.description_outlined,
                              AppStrings.attachDocument),
                          _attachItem('voice', Icons.mic, AppStrings.attachVoice),
                        ],
                        builder: (
                          BuildContext context,
                          MenuController controller,
                          Widget? child,
                        ) {
                          return OutlinedButton.icon(
                            onPressed: () {
                              if (controller.isOpen) {
                                controller.close();
                              } else {
                                controller.open();
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text(AppStrings.attachmentsLabel),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Row(
                children: <Widget>[
                  if (widget.existing != null)
                    TextButton.icon(
                      onPressed: _saving ? null : () => unawaited(_delete()),
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
            ),
          ],
        ),
      ),
    );
  }

  MenuItemButton _attachItem(String kind, IconData icon, String label) {
    return MenuItemButton(
      leadingIcon: Icon(icon),
      onPressed: () => unawaited(_addAttachment(kind)),
      child: Text(label),
    );
  }
}
