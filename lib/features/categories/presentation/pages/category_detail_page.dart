import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../notes/domain/entities/note.dart';
import '../../../notes/presentation/providers/note_providers.dart';
import '../../../notes/presentation/widgets/note_row.dart';
import '../../../notes/presentation/widgets/note_sheet.dart';
import '../../../todos/domain/entities/todo.dart';
import '../../../todos/presentation/providers/todo_providers.dart';
import '../../../todos/presentation/widgets/todo_editor_sheet.dart';
import '../../../todos/presentation/widgets/todo_list_view.dart';
import '../../domain/entities/category.dart';
import '../providers/category_providers.dart';

/// What the folder is showing.
enum _Pane { todos, notes }

/// Everything filed inside one folder, with a search box that looks only here.
///
/// A separate screen rather than a filter on the main list: the point of a
/// folder is that opening it narrows what you are looking at, and a filter that
/// can be forgotten about somewhere else does not do that.
class CategoryDetailPage extends ConsumerStatefulWidget {
  const CategoryDetailPage({required this.category, super.key});

  /// The folder being shown, or `null` for the unfiled pile.
  final Category? category;

  @override
  ConsumerState<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends ConsumerState<CategoryDetailPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Folders hold two kinds of thing, and they are read differently: what is
  /// left to do, and what was written about it. Same switch as the calendar's,
  /// so there is one way to move between the two in this app.
  _Pane _pane = _Pane.todos;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Todo> todos = ref.watch(todoListProvider).value ?? const <Todo>[];
    final List<Note> notes = ref.watch(notesProvider).value ?? const <Note>[];
    final DateTime now = ref.read(clockProvider)();
    final String? categoryId = widget.category?.id;

    // One pass each: the folder test and the query test together, and the same
    // rule the folders screen counts by — an id whose folder no longer exists
    // counts as unfiled.
    final Set<String> known = <String>{
      for (final Category category
          in ref.watch(categoriesProvider).value ?? const <Category>[])
        category.id,
    };
    final String needle = _query.trim().toLowerCase();
    final List<Todo> visibleTodos = <Todo>[
      for (final Todo todo in todos)
        if (_belongs(todo.categoryId, categoryId, known) &&
            _todoMatches(todo, needle))
          todo,
    ];
    final List<Note> visibleNotes = <Note>[
      for (final Note note in notes)
        if (_belongs(note.categoryId, categoryId, known) &&
            _noteMatches(note, needle))
          note,
    ]..sort((Note a, Note b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category?.name ?? AppStrings.categoryUnfiled),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_create(categoryId)),
        icon: const Icon(Icons.add),
        label: Text(
          _pane == _Pane.notes ? AppStrings.noteAdd : AppStrings.newTodo,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _searchController,
              onChanged: (String value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: AppStrings.categorySearchHint,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: AppStrings.clearSearch,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_Pane>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<_Pane>>[
                ButtonSegment<_Pane>(
                  value: _Pane.todos,
                  label: Text(AppStrings.categoryPaneTodos),
                  icon: Icon(Icons.checklist),
                ),
                ButtonSegment<_Pane>(
                  value: _Pane.notes,
                  label: Text(AppStrings.noteSection),
                  icon: Icon(Icons.edit_note),
                ),
              ],
              selected: <_Pane>{_pane},
              onSelectionChanged: (Set<_Pane> selection) =>
                  setState(() => _pane = selection.first),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_pane) {
                _Pane.todos => _todoList(visibleTodos, now),
                _Pane.notes => _noteList(visibleNotes, now),
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(String? categoryId) {
    return _pane == _Pane.notes
        ? showNoteSheet(
            context,
            date: ref.read(clockProvider)(),
            initialCategoryId: categoryId,
          )
        : showTodoEditor(context, initialCategoryId: categoryId);
  }

  Widget _todoList(List<Todo> visible, DateTime now) {
    if (visible.isEmpty) {
      return _empty(_query.isEmpty
          ? AppStrings.categoryFolderEmpty
          : AppStrings.emptySearchTitle);
    }
    return TodoListView(
      todos: visible,
      now: now,
      // Inside a folder the order is still the manual one, so dragging works the
      // same way it does on the main list.
      allowReorder: true,
    );
  }

  Widget _noteList(List<Note> visible, DateTime now) {
    if (visible.isEmpty) {
      // A search that finds no notes should not talk about todos.
      return _empty(_query.isEmpty
          ? AppStrings.noteFolderEmpty
          : AppStrings.noteSearchEmpty);
    }
    return ListView(
      children: <Widget>[
        for (final Note note in visible)
          NoteRow(
            note: note,
            now: now,
            onTap: () => unawaited(
              showNoteSheet(context, existing: note, date: note.date),
            ),
          ),
      ],
    );
  }

  Widget _empty(String message) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  /// Whether an entry filed under [entryCategoryId] belongs in this folder.
  static bool _belongs(
    String? entryCategoryId,
    String? folderId,
    Set<String> known,
  ) {
    final bool unfiled = entryCategoryId == null || !known.contains(entryCategoryId);
    return folderId == null ? unfiled : entryCategoryId == folderId;
  }

  static bool _todoMatches(Todo todo, String needle) {
    if (needle.isEmpty) {
      return true;
    }
    return todo.title.toLowerCase().contains(needle) ||
        (todo.notes?.toLowerCase().contains(needle) ?? false);
  }

  static bool _noteMatches(Note note, String needle) {
    if (needle.isEmpty) {
      return true;
    }
    return note.body.toLowerCase().contains(needle) ||
        note.attachments.any(
          (attachment) => attachment.name.toLowerCase().contains(needle),
        );
  }
}
