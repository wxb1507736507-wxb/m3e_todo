import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../../../core/utils/calendar.dart';
import '../../../todos/presentation/providers/todo_providers.dart';
import '../../domain/entities/special_day.dart';
import '../providers/special_day_providers.dart';

/// Opens the editor for a birthday, anniversary or countdown.
///
/// Pass [existing] to edit one; omit it to add. Mirrors the todo editor's shape
/// (a modal sheet, a form, save/cancel) because it is the same interaction, just
/// with fewer fields.
Future<void> showSpecialDaySheet(BuildContext context, {SpecialDay? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SpecialDaySheet(existing: existing),
  );
}

class SpecialDaySheet extends ConsumerStatefulWidget {
  const SpecialDaySheet({this.existing, super.key});

  final SpecialDay? existing;

  @override
  ConsumerState<SpecialDaySheet> createState() => _SpecialDaySheetState();
}

class _SpecialDaySheetState extends ConsumerState<SpecialDaySheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late SpecialDayKind _kind;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final SpecialDay? existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _kind = existing?.kind ?? SpecialDayKind.birthday;
    _date = existing?.date ?? startOfDay(ref.read(clockProvider)());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = ref.read(clockProvider)();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // Back to a plausible birth year and far enough forward for any countdown
      // anyone would enter, without letting a slip of the finger land in 1900.
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year + 50, 12, 31),
      helpText: AppStrings.specialDayDateHelp,
    );
    if (picked != null && mounted) {
      setState(() => _date = startOfDay(picked));
    }
  }

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final SpecialDaysController controller =
        ref.read(specialDaysProvider.notifier);

    try {
      final SpecialDay? existing = widget.existing;
      if (existing == null) {
        await controller.add(
          title: _titleController.text,
          kind: _kind,
          date: _date,
          notes: _notesController.text,
        );
      } else {
        await controller.edit(
          existing.id,
          title: _titleController.text,
          kind: _kind,
          date: _date,
          notes: _notesController.text,
        );
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

  Future<void> _delete() async {
    final SpecialDay? existing = widget.existing;
    if (existing == null) {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(specialDaysProvider.notifier).remove(existing.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(AppStrings.specialDayDeleted(existing.title))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final TextTheme text = theme.textTheme;
    final DateTime now = ref.read(clockProvider)();
    final bool yearly = _kind.repeatsYearly;

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
                        widget.existing == null
                            ? AppStrings.specialDayNew
                            : AppStrings.specialDayEdit,
                        style: text.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: AppStrings.titleLabel,
                          hintText: AppStrings.specialDayTitleHint,
                        ),
                        validator: (String? value) =>
                            (value == null || value.trim().isEmpty)
                                ? AppStrings.titleRequired
                                : null,
                      ),
                      const SizedBox(height: 20),
                      Text(AppStrings.specialDayKindLabel, style: text.labelLarge),
                      const SizedBox(height: 8),
                      // A Wrap, not a Row: three chips and their labels do not
                      // fit across a phone, and a rendered overflow paints
                      // stripes over the last one.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final (SpecialDayKind kind, String label)
                              in <(SpecialDayKind, String)>[
                            (SpecialDayKind.birthday, AppStrings.specialDayBirthday),
                            (SpecialDayKind.anniversary, AppStrings.specialDayAnniversary),
                            (SpecialDayKind.countdown, AppStrings.specialDayCountdown),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _kind == kind,
                              onSelected: (_) => setState(() => _kind = kind),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        yearly
                            ? AppStrings.specialDayYearlyHint
                            : AppStrings.specialDayCountdownHint,
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  yearly
                                      ? AppStrings.specialDayDateLabel
                                      : AppStrings.specialDayTargetLabel,
                                  style: text.labelLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppDateFormatter.calendarDate(_date, now),
                                  style: text.bodyLarge,
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => unawaited(_pickDate()),
                            icon: const Icon(Icons.event_outlined),
                            label: const Text(AppStrings.pickDueDate),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: AppStrings.notesLabel,
                          hintText: AppStrings.notesHint,
                        ),
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
}
