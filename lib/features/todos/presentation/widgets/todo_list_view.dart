import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_motion.dart';
import '../../domain/entities/todo.dart';
import '../../domain/usecases/delete_todo.dart';
import '../controllers/todo_list_controller.dart';
import '../providers/todo_providers.dart';
import 'todo_editor_sheet.dart';
import 'todo_tile.dart';

/// The scrollable list of todos.
///
/// Always a [ReorderableListView], even when reordering is currently disabled:
/// the only thing that starts a drag is the handle inside [TodoTile], and that
/// handle is simply not built when a sort rule owns the order. Using one widget
/// for both cases keeps spacing and drag behaviour identical instead of drifting
/// apart between two code paths.
class TodoListView extends ConsumerWidget {
  const TodoListView({
    required this.todos,
    required this.now,
    required this.allowReorder,
    super.key,
  });

  final List<Todo> todos;
  final DateTime now;
  final bool allowReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      buildDefaultDragHandles: false,
      itemCount: todos.length,
      onReorderItem: (int oldIndex, int newIndex) => unawaited(
        _guard(
          ScaffoldMessenger.of(context),
          () => ref
              .read(todoListProvider.notifier)
              .reorder(oldIndex, newIndex),
        ),
      ),
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (BuildContext context, Widget? _) {
            final double t =
                AppMotion.spatialFast.curve.transform(animation.value);
            return Transform.scale(scale: 1 + 0.02 * t, child: child);
          },
        );
      },
      itemBuilder: (BuildContext context, int index) {
        final Todo todo = todos[index];
        return Padding(
          key: ValueKey<String>(todo.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: TodoTile(
            todo: todo,
            now: now,
            dragIndex: allowReorder ? index : null,
            onToggle: () => unawaited(
              _guard(
                ScaffoldMessenger.of(context),
                () => ref.read(todoListProvider.notifier).toggle(todo.id),
              ),
            ),
            onEdit: () => showTodoEditor(context, existing: todo),
            onDelete: () =>
                unawaited(_delete(context, ref, todo)),
          ),
        );
      },
    );
  }

  /// Deletes [todo] and offers an undo that restores it to its old position.
  Future<void> _delete(BuildContext context, WidgetRef ref, Todo todo) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final TodoListController controller = ref.read(todoListProvider.notifier);

    try {
      final TodoDeletion deletion = await controller.delete(todo.id);
      if (!deletion.removedSomething) {
        return;
      }
      final Todo removed = deletion.removed!;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppStrings.deletedTodo(todo.title)),
            action: SnackBarAction(
              label: AppStrings.undo,
              onPressed: () => unawaited(
                _guard(
                  messenger,
                  () => controller.restore(removed, deletion.index),
                ),
              ),
            ),
          ),
        );
    } on Object catch (error) {
      messenger.showSnackBar(_failure(error));
    }
  }

  static SnackBar _failure(Object error) {
    return SnackBar(content: Text('${AppStrings.saveFailed}：$error'));
  }

  /// Runs a write and reports any failure, so a storage problem surfaces as a
  /// message instead of an unhandled exception in the console.
  static Future<void> _guard(
    ScaffoldMessengerState messenger,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object catch (error) {
      messenger.showSnackBar(_failure(error));
    }
  }
}
