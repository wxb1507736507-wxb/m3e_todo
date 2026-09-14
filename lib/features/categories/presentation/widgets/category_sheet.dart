import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_palette.dart';
import '../providers/category_providers.dart';
import '../../domain/entities/category.dart';

/// Opens the editor for a folder: name and colour, plus delete when editing.
///
/// Returns the folder that was created or edited, or `null` if the sheet was
/// dismissed — which lets a caller that opened it *to file something* select
/// what the user just made instead of making them pick it again.
Future<Category?> showCategorySheet(
  BuildContext context, {
  Category? existing,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CategorySheet(existing: existing),
  );
}

/// The colours a folder can be marked with.
///
/// A short list rather than the full palette the tiles use: a folder's colour is
/// a label, not a design decision, and eight is enough to tell a handful of
/// folders apart at a glance.
const List<AppPaletteColor> kCategoryColors = <AppPaletteColor>[
  AppPaletteColor(0xFFE53935, '红'),
  AppPaletteColor(0xFFFB8C00, '橙'),
  AppPaletteColor(0xFFFDD835, '黄'),
  AppPaletteColor(0xFF43A047, '绿'),
  AppPaletteColor(0xFF00897B, '青绿'),
  AppPaletteColor(0xFF1E88E5, '蓝'),
  AppPaletteColor(0xFF8E24AA, '紫'),
  AppPaletteColor(0xFF6D4C41, '棕'),
];

class CategorySheet extends ConsumerStatefulWidget {
  const CategorySheet({this.existing, super.key});

  final Category? existing;

  @override
  ConsumerState<CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<CategorySheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late int? _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _color = widget.existing?.color;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final CategoriesController controller = ref.read(categoriesProvider.notifier);

    try {
      final Category? existing = widget.existing;
      final Category saved;
      if (existing == null) {
        saved = await controller.add(name: _nameController.text, color: _color);
      } else {
        await controller.edit(
          existing.id,
          name: _nameController.text,
          color: _color,
        );
        saved = existing.edited(name: _nameController.text, color: _color);
      }
      navigator.pop(saved);
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
    final Category? existing = widget.existing;
    if (existing == null) {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(categoriesProvider.notifier).remove(existing.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(AppStrings.categoryDeleted(existing.name))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                    ? AppStrings.categoryNew
                    : AppStrings.categoryEdit,
                style: text.headlineSmall,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                autofocus: widget.existing == null,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: AppStrings.categoryNameLabel,
                  hintText: AppStrings.categoryNameHint,
                ),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty)
                        ? AppStrings.categoryNameRequired
                        : null,
                onFieldSubmitted: (_) => unawaited(_submit()),
              ),
              const SizedBox(height: 20),
              Text(AppStrings.categoryColorLabel, style: text.labelLarge),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final AppPaletteColor option in kCategoryColors)
                    _ColorSwatch(
                      argb: option.argb,
                      label: option.label,
                      selected: _color == option.argb,
                      onTap: () => setState(() {
                        // Tapping the chosen colour again clears it, so "no
                        // colour" stays reachable without a separate control.
                        _color = _color == option.argb ? null : option.argb;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
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
              const SizedBox(height: 4),
              Text(
                AppStrings.categoryDeleteHint,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round colour swatch with the same selected/unselected treatment the tile
/// colours use.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(argb),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
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
