import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../domain/entities/category.dart';
import '../providers/category_providers.dart';
import 'category_sheet.dart';

/// The folder picker shown inside the todo and note editors.
///
/// Shared so the two cannot drift, and so there is exactly one answer to "where
/// do I put this?" in the app.
///
/// It also creates folders, which is why it is always visible rather than only
/// when folders exist: the moment a user realises they want a new folder is the
/// moment they are filing something, and sending them to another screen to make
/// one is how a grouping feature ends up unused.
class CategoryPicker extends ConsumerWidget {
  const CategoryPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The chosen folder, or `null` for unfiled.
  final String? value;

  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Category> categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(AppStrings.categoryPickLabel, style: text.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text(AppStrings.categoryUnfiled),
              selected: value == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final Category category in categories)
              ChoiceChip(
                avatar: category.color == null
                    ? null
                    : CircleAvatar(backgroundColor: Color(category.color!)),
                label: Text(category.name),
                selected: value == category.id,
                onSelected: (_) => onChanged(category.id),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text(AppStrings.categoryNew),
              onPressed: () => unawaited(_create(context)),
            ),
          ],
        ),
      ],
    );
  }

  /// Makes a folder and files the entry under it straight away.
  ///
  /// The user opened this to file something; asking them to pick the folder they
  /// just named would be a second step for the same decision.
  Future<void> _create(BuildContext context) async {
    final Category? created = await showCategorySheet(context);
    if (created != null) {
      onChanged(created.id);
    }
  }
}
