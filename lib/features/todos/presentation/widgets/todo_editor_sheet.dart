import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/platform/app_platform.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../media/presentation/color_extract_page.dart';
import '../../../media/presentation/image_crop_page.dart';
import '../../domain/entities/todo.dart';
import '../../domain/entities/todo_attachment.dart';
import '../../domain/entities/todo_draft.dart';
import '../../domain/entities/todo_priority.dart';
import '../../domain/entities/todo_subtask.dart';
import '../controllers/todo_list_controller.dart';
import '../providers/todo_providers.dart';
import 'attachment_actions.dart';
import 'color_field.dart';

/// Opens the create/edit sheet and completes when it closes.
///
/// A modal bottom sheet rather than a dialog: the list stays visible behind the
/// form, which matters on a desktop window where the list is the context for
/// whatever is being edited.
Future<void> showTodoEditor(BuildContext context, {Todo? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (BuildContext context) => TodoEditorSheet(existing: existing),
  );
}

/// One editable subtask row inside the form.
class _SubtaskRow {
  _SubtaskRow({required this.id, required String initial, this.completedAt}) {
    controller = TextEditingController(text: initial);
  }

  final String id;
  DateTime? completedAt;
  late final TextEditingController controller;

  void dispose() => controller.dispose();
}

/// Form for creating a todo or editing an existing one.
///
/// Holds the draft in local widget state and only talks to the controller on
/// submit, so an abandoned edit leaves no trace and the stored collection is
/// written at most once per save.
class TodoEditorSheet extends ConsumerStatefulWidget {
  const TodoEditorSheet({this.existing, super.key});

  /// The todo being edited, or `null` when creating a new one.
  final Todo? existing;

  @override
  ConsumerState<TodoEditorSheet> createState() => _TodoEditorSheetState();
}

class _TodoEditorSheetState extends ConsumerState<TodoEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late TodoPriority _priority;
  DateTime? _dueDate;
  List<_SubtaskRow> _subtaskRows = <_SubtaskRow>[];
  List<TodoAttachment> _attachments = <TodoAttachment>[];
  int? _accentColor;
  int? _textColor;
  String? _backgroundImage;
  bool _saving = false;

  /// Files the native picker/recorder copied into the app directory *during this
  /// editing session*.
  ///
  /// The copy happens as soon as the user picks, before anything is saved, so an
  /// abandoned edit would otherwise leave the file behind forever — nothing else
  /// ever references it. Tracking them here lets [dispose] clean up exactly the
  /// files this session created, and nothing else.
  final Set<String> _newFiles = <String>{};

  /// Whether the sheet was dismissed by submitting, so the files now belong to
  /// a stored todo and must survive.
  bool _saved = false;

  /// Files the *stored* todo referenced that the edit has dropped (a replaced
  /// background, a removed attachment, and so on).
  ///
  /// Deleted only after a successful save: until then the stored todo still
  /// points at them, and cancelling must change nothing.
  final Set<String> _obsoleteFiles = <String>{};

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Todo? existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _priority = existing?.priority ?? TodoPriority.normal;
    _dueDate = existing?.dueDate;
    _subtaskRows = <_SubtaskRow>[
      for (final TodoSubtask subtask in existing?.subtasks ?? const <TodoSubtask>[])
        _SubtaskRow(
          id: subtask.id,
          initial: subtask.title,
          completedAt: subtask.completedAt,
        ),
    ];
    _attachments = List<TodoAttachment>.of(existing?.attachments ?? const <TodoAttachment>[]);
    _accentColor = existing?.accentColor;
    _textColor = existing?.textColor;
    _backgroundImage = existing?.backgroundImage;
  }

  @override
  void dispose() {
    if (!_saved) {
      _deleteAbandonedFiles();
    }
    _titleController.dispose();
    _notesController.dispose();
    for (final _SubtaskRow row in _subtaskRows) {
      row.dispose();
    }
    super.dispose();
  }

  /// Removes the copies this session made but never stored.
  ///
  /// [_newFiles] only ever holds files the picker/recorder created during *this*
  /// session, so an abandoned sheet deletes all of them — no "keep" set is
  /// needed, and trying to build one from the sheet's own state was a bug: the
  /// attachment the user just added is still listed there, so nothing was ever
  /// deleted.
  ///
  /// Deleting is best-effort: a file that cannot be removed (already gone, or
  /// locked) is not worth reporting to a user who just pressed "cancel".
  void _deleteAbandonedFiles() {
    for (final String path in _newFiles) {
      _deleteFile(path);
    }
    _newFiles.clear();
  }

  static void _deleteFile(String path) {
    unawaited(File(path).delete().catchError((Object _) => File(path)));
  }

  Future<void> _pickDueDate() async {
    final DateTime now = ref.read(clockProvider)();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _dueDate = picked);
  }

  // --- Subtasks ---------------------------------------------------------------

  void _addSubtaskRow() {
    setState(() {
      _subtaskRows = <_SubtaskRow>[
        ..._subtaskRows,
        _SubtaskRow(id: ref.read(idGeneratorProvider)(), initial: ''),
      ];
    });
  }

  void _removeSubtaskRow(_SubtaskRow row) {
    setState(() {
      row.dispose();
      _subtaskRows = <_SubtaskRow>[..._subtaskRows]..remove(row);
    });
  }

  // --- Attachments ---------------------------------------------------------------

  Future<void> _addAttachment(_AttachmentKind kind) async {
    if (!attachmentsSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.attachmentUnsupported)),
      );
      return;
    }
    TodoAttachment? attachment;
    if (kind == _AttachmentKind.voice) {
      attachment = await recordVoiceAttachment(context, ref);
    } else {
      attachment = await pickAndCreateAttachment(context, ref, kind.name);
    }
    if (attachment == null || !mounted) {
      return;
    }
    final TodoAttachment added = attachment;
    // Both branches above (picker, recorder) copy a *new* file into the app
    // directory, so it belongs to this session.
    _newFiles.add(added.path);
    setState(
      () => _attachments = <TodoAttachment>[..._attachments, added],
    );
  }

  void _removeAttachment(TodoAttachment attachment) {
    // A file this session created has just become unreferenced, so drop it now
    // instead of waiting for dispose: the user may well save the todo, and a
    // saved todo would otherwise leave the file behind for good. A file the
    // stored todo owned is retired only once the save succeeds.
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

  Future<void> _pickBackgroundImage() async {
    if (!attachmentsSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.attachmentUnsupported)),
      );
      return;
    }
    // Cropped on the way in: a tile is a wide, short rectangle, so an untreated
    // photo would be reduced to a meaningless middle strip.
    final CroppedImage? cropped = await pickAndCropImage(
      context,
      initialAspect: CropAspect.wide,
    );
    if (cropped == null || !mounted) {
      return;
    }
    _setBackgroundImage(cropped.path);
  }

  /// Re-crops the image already on this todo, so the user can reframe without
  /// hunting for the original file again.
  Future<void> _cropCurrentBackground() async {
    final String? current = _backgroundImage;
    if (current == null) {
      return;
    }
    final CroppedImage? cropped = await cropImage(
      context,
      sourcePath: current,
      initialAspect: CropAspect.wide,
    );
    if (cropped == null || !mounted) {
      return;
    }
    _setBackgroundImage(cropped.path);
  }

  /// Points the todo at [path] and retires whatever it pointed at before.
  ///
  /// A file created in this session goes immediately; one that belonged to the
  /// stored todo is only retired on a successful save, because cancelling must
  /// leave the stored todo exactly as it was.
  void _setBackgroundImage(String? path) {
    final String? previous = _backgroundImage;
    if (previous != null && previous != path) {
      if (!_newFiles.remove(previous)) {
        _obsoleteFiles.add(previous);
      } else {
        _deleteFile(previous);
      }
    }
    if (path != null && !_newFiles.contains(path)) {
      _newFiles.add(path);
    }
    setState(() => _backgroundImage = path);
  }

  void _removeBackgroundImage() => _setBackgroundImage(null);

  /// Samples a colour from a picture for either colour field.
  ///
  /// Prefers the todo's own background image — it is the picture the card will
  /// actually show, so picking a colour out of it is the obvious move. With no
  /// background image the user picks one just for sampling, and that copy is
  /// deleted again afterwards: nothing references it, and leaving it behind is
  /// exactly the leak the attachment flows had to be fixed for.
  Future<int?> _sampleColor() async {
    final String? background = _backgroundImage;
    if (background != null) {
      return extractColorFromImage(context, imagePath: background);
    }
    final PickedAttachment? picked = await AppPlatform.pickAttachment('image');
    if (picked == null || !mounted) {
      return null;
    }
    final int? sampled =
        await extractColorFromImage(context, imagePath: picked.path);
    unawaited(File(picked.path).delete().catchError((Object _) => File(picked.path)));
    return sampled;
  }

  /// Warns when the chosen text colour cannot be read on the chosen card.
  ///
  /// Only for an explicit text colour on an explicit card colour: with either
  /// side on "auto" the theme already guarantees contrast, and with a
  /// background image the scrim does.
  String? get _contrastWarning {
    final int? text = _textColor;
    final int? card = _accentColor;
    if (text == null || card == null || _backgroundImage != null) {
      return null;
    }
    return isHardToRead(text, card) ? AppStrings.colorContrastWarning : null;
  }

  // --- Submit ----------------------------------------------------------------------

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);

    // Resolved before the first await: looking them up afterwards would trip
    // the "don't use BuildContext across an async gap" rule, and the sheet may
    // already be animating away by then.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final TodoListController controller = ref.read(todoListProvider.notifier);

    final TodoDraft draft = TodoDraft(
      title: _titleController.text,
      notes: _notesController.text,
      priority: _priority,
      dueDate: _dueDate,
      subtasks: <TodoSubtask>[
        // Blank rows are simply skipped: a half-typed subtask the user meant
        // to delete should not block saving.
        for (final _SubtaskRow row in _subtaskRows)
          if (row.controller.text.trim().isNotEmpty)
            TodoSubtask(id: row.id, title: row.controller.text, completedAt: row.completedAt),
      ],
      attachments: _attachments,
      accentColor: _accentColor,
      textColor: _textColor,
      backgroundImage: _backgroundImage,
    );

    try {
      final Todo? existing = widget.existing;
      if (existing == null) {
        await controller.add(draft);
      } else {
        await controller.edit(existing.id, draft);
      }
      // Marked before popping: dispose() runs during the pop and must not delete
      // files that a stored todo now references.
      _saved = true;
      // The save replaced the stored todo, so anything it dropped is now
      // genuinely unreferenced.
      for (final String path in _obsoleteFiles) {
        _deleteFile(path);
      }
      _obsoleteFiles.clear();
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

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colors = Theme.of(context).colorScheme;

    // The form scrolls; the action bar does not. Pinning the bar below the
    // scrollable (and padding the whole sheet by the keyboard inset) keeps the
    // confirm button reachable no matter how much content the keyboard hides.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
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
                        _isEditing ? AppStrings.editTodo : AppStrings.newTodo,
                        style: text.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: AppStrings.titleLabel,
                          hintText: AppStrings.titleHint,
                        ),
                        validator: (String? value) =>
                            (value == null || value.trim().isEmpty)
                                ? AppStrings.titleRequired
                                : null,
                        onFieldSubmitted: (_) => unawaited(_submit()),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: AppStrings.notesLabel,
                          hintText: AppStrings.notesHint,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(AppStrings.priorityLabel, style: text.labelLarge),
                      const SizedBox(height: 8),
                      SegmentedButton<TodoPriority>(
                        showSelectedIcon: false,
                        segments: const <ButtonSegment<TodoPriority>>[
                          ButtonSegment<TodoPriority>(
                            value: TodoPriority.low,
                            label: Text(AppStrings.priorityLow),
                            icon: Icon(Icons.keyboard_arrow_down),
                          ),
                          ButtonSegment<TodoPriority>(
                            value: TodoPriority.normal,
                            label: Text(AppStrings.priorityNormal),
                            icon: Icon(Icons.drag_handle),
                          ),
                          ButtonSegment<TodoPriority>(
                            value: TodoPriority.high,
                            label: Text(AppStrings.priorityHigh),
                            icon: Icon(Icons.keyboard_arrow_up),
                          ),
                        ],
                        selected: <TodoPriority>{_priority},
                        onSelectionChanged: (Set<TodoPriority> selection) =>
                            setState(() => _priority = selection.first),
                      ),
                      const SizedBox(height: 24),
                      Text(AppStrings.dueDateLabel, style: text.labelLarge),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _dueDate == null
                                  ? AppStrings.dueDateUnset
                                  : AppDateFormatter.calendarDate(
                                      _dueDate!,
                                      ref.read(clockProvider)(),
                                    ),
                              style: text.bodyLarge?.copyWith(
                                color: _dueDate == null
                                    ? colors.onSurfaceVariant
                                    : colors.onSurface,
                              ),
                            ),
                          ),
                          if (_dueDate != null)
                            TextButton(
                              onPressed: () => setState(() => _dueDate = null),
                              child: const Text(AppStrings.clearDueDate),
                            ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => unawaited(_pickDueDate()),
                            icon: const Icon(Icons.event_outlined),
                            label: const Text(AppStrings.pickDueDate),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSubtasksSection(text, colors),
                      const SizedBox(height: 24),
                      _buildAttachmentsSection(text, colors),
                      const SizedBox(height: 24),
                      _buildAppearanceSection(text, colors),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text(AppStrings.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => unawaited(_submit()),
                    icon: Icon(_isEditing ? Icons.check : Icons.add),
                    label: Text(
                      _isEditing ? AppStrings.save : AppStrings.create,
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

  // --- Sections ----------------------------------------------------------------------

  Widget _buildSubtasksSection(TextTheme text, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(AppStrings.subtasksLabel, style: text.labelLarge)),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: AppStrings.addSubtask,
              onPressed: _addSubtaskRow,
            ),
          ],
        ),
        if (_subtaskRows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              AppStrings.subtaskEmptyHint,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          )
        else
          Column(
            children: <Widget>[
              for (final _SubtaskRow row in _subtaskRows)
                Padding(
                  key: ValueKey<String>(row.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: row.controller,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: AppStrings.subtaskHint,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: AppStrings.removeSubtask,
                        onPressed: () => _removeSubtaskRow(row),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildAttachmentsSection(TextTheme text, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(AppStrings.attachmentsLabel, style: text.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final TodoAttachment attachment in _attachments)
              _AttachmentChip(
                attachment: attachment,
                onOpen: () => unawaited(_openAttachment(attachment)),
                onRemove: () => _removeAttachment(attachment),
              ),
          ],
        ),
        const SizedBox(height: 8),
        MenuAnchor(
          menuChildren: <Widget>[
            _attachMenuItem(_AttachmentKind.image, Icons.image_outlined),
            _attachMenuItem(_AttachmentKind.video, Icons.videocam_outlined),
            _attachMenuItem(_AttachmentKind.document, Icons.description_outlined),
            _attachMenuItem(_AttachmentKind.voice, Icons.mic),
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
    );
  }

  MenuItemButton _attachMenuItem(_AttachmentKind kind, IconData icon) {
    return MenuItemButton(
      leadingIcon: Icon(icon),
      onPressed: () => unawaited(_addAttachment(kind)),
      child: Text(switch (kind) {
        _AttachmentKind.image => AppStrings.attachImage,
        _AttachmentKind.video => AppStrings.attachVideo,
        _AttachmentKind.document => AppStrings.attachDocument,
        _AttachmentKind.voice => AppStrings.attachVoice,
      }),
    );
  }

  Widget _buildAppearanceSection(TextTheme text, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ColorField(
          label: AppStrings.accentColorLabel,
          value: _accentColor,
          noneLabel: AppStrings.accentColorNone,
          presets: kCommonColors,
          onChanged: (int? value) => setState(() => _accentColor = value),
          onSample: _sampleColor,
        ),
        const SizedBox(height: 20),
        ColorField(
          label: AppStrings.textColorLabel,
          value: _textColor,
          noneLabel: AppStrings.textColorAuto,
          presets: kSoftColors,
          onChanged: (int? value) => setState(() => _textColor = value),
          onSample: _sampleColor,
          warning: _contrastWarning,
        ),
        const SizedBox(height: 16),
        // The label gets its own line and the actions live in a `Wrap`: with a
        // picture set there are three buttons here, and a phone is not wide
        // enough for them beside the label — as a `Row` they overflowed, and
        // Flutter painted its striped overflow banner over the last button.
        Text(AppStrings.backgroundImageLabel, style: text.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () => unawaited(_pickBackgroundImage()),
              icon: const Icon(Icons.wallpaper_outlined),
              label: const Text(AppStrings.pickBackgroundImage),
            ),
            if (_backgroundImage != null)
              OutlinedButton.icon(
                onPressed: () => unawaited(_cropCurrentBackground()),
                icon: const Icon(Icons.crop),
                label: const Text(AppStrings.cropBackgroundImage),
              ),
            if (_backgroundImage != null)
              TextButton.icon(
                onPressed: _removeBackgroundImage,
                icon: const Icon(Icons.delete_outline),
                label: const Text(AppStrings.clearBackgroundImage),
              ),
          ],
        ),
        if (_backgroundImage != null) ...<Widget>[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppShapes.small),
            child: SizedBox(
              height: 96,
              width: double.infinity,
              child: Image.file(
                File(_backgroundImage!),
                fit: BoxFit.cover,
                // The preview is 96dp tall; decoding the full crop for it would
                // cost several megabytes of bitmap for a stamp-sized strip.
                cacheWidth: 320,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _AttachmentKind { image, video, document, voice }

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.onOpen,
    required this.onRemove,
  });

  final TodoAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return InputChip(
      avatar: AttachmentThumb(attachment: attachment, size: 28),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Text(
          attachment.name,
          overflow: TextOverflow.ellipsis,
          style: text.labelMedium,
        ),
      ),
      backgroundColor: colors.surfaceContainerHigh,
      onDeleted: onRemove,
      onPressed: onOpen,
    );
  }
}

