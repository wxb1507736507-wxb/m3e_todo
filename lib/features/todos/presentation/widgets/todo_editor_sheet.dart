import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../domain/entities/todo.dart';
import '../../domain/entities/todo_draft.dart';
import '../../domain/entities/todo_priority.dart';
import '../controllers/todo_list_controller.dart';
import '../providers/todo_providers.dart';

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
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Todo? existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _priority = existing?.priority ?? TodoPriority.normal;
    _dueDate = existing?.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
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
    );

    try {
      final Todo? existing = widget.existing;
      if (existing == null) {
        await controller.add(draft);
      } else {
        await controller.edit(existing.id, draft);
      }
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

    return Padding(
      // Lifts the form above the on-screen keyboard on touch hardware; a no-op
      // on a desktop window.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
                autofocus: true,
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
              const SizedBox(height: 28),
              Row(
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
            ],
          ),
        ),
      ),
    );
  }
}
