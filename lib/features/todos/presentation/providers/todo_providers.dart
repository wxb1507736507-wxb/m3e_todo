import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/document_store.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/id_generator.dart';
import '../../data/datasources/todo_local_data_source.dart';
import '../../data/repositories/local_todo_repository.dart';
import '../../domain/entities/todo.dart';
import '../../domain/entities/todo_filter.dart';
import '../../domain/entities/todo_stats.dart';
import '../../domain/repositories/todo_repository.dart';
import '../../domain/usecases/add_todo.dart';
import '../../domain/usecases/clear_completed_todos.dart';
import '../../domain/usecases/delete_todo.dart';
import '../../domain/usecases/load_todos.dart';
import '../../domain/usecases/reorder_todos.dart';
import '../../domain/usecases/restore_todo.dart';
import '../../domain/usecases/toggle_todo.dart';
import '../../domain/usecases/update_todo.dart';
import '../controllers/todo_filter_controller.dart';
import '../controllers/todo_list_controller.dart';

/// File name of the todo document inside the app data directory.
const String todoFileName = 'todos.json';

// --- Infrastructure --------------------------------------------------------

/// The JSON document backing the todo list.
///
/// Asked for by name; whether that becomes a file or a `localStorage` entry is
/// decided by the platform-selected factory, not here.
final Provider<DocumentStore> todoDocumentStoreProvider = Provider<DocumentStore>(
  (ref) => ref.watch(documentStoreFactoryProvider)(todoFileName),
  name: 'todoDocumentStore',
);

/// Swapping this single override is what would move the app to another storage
/// backend, because everything above it depends on [TodoRepository] only.
final Provider<TodoRepository> todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => LocalTodoRepository(
    TodoLocalDataSource(ref.watch(todoDocumentStoreProvider)),
  ),
  name: 'todoRepository',
);

/// Source of todo ids. Overridden in tests with a deterministic sequence.
final Provider<IdGenerator> idGeneratorProvider = Provider<IdGenerator>(
  (ref) => generateTodoId,
  name: 'idGenerator',
);

/// Source of "now". Overridden in tests so overdue logic is reproducible.
final Provider<Clock> clockProvider = Provider<Clock>(
  (ref) => systemClock,
  name: 'clock',
);

// --- Use cases -------------------------------------------------------------
//
// Each use case is exposed as its own provider so it can be read in isolation
// and swapped in a test without rebuilding the whole graph.

final Provider<LoadTodos> loadTodosProvider = Provider<LoadTodos>(
  (ref) => LoadTodos(ref.watch(todoRepositoryProvider)),
  name: 'loadTodos',
);

final Provider<AddTodo> addTodoProvider = Provider<AddTodo>(
  (ref) => AddTodo(
    ref.watch(todoRepositoryProvider),
    idGenerator: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'addTodo',
);

final Provider<UpdateTodo> updateTodoProvider = Provider<UpdateTodo>(
  (ref) => UpdateTodo(ref.watch(todoRepositoryProvider)),
  name: 'updateTodo',
);

final Provider<ToggleTodo> toggleTodoProvider = Provider<ToggleTodo>(
  (ref) => ToggleTodo(
    ref.watch(todoRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'toggleTodo',
);

final Provider<DeleteTodo> deleteTodoProvider = Provider<DeleteTodo>(
  (ref) => DeleteTodo(ref.watch(todoRepositoryProvider)),
  name: 'deleteTodo',
);

final Provider<RestoreTodo> restoreTodoProvider = Provider<RestoreTodo>(
  (ref) => RestoreTodo(ref.watch(todoRepositoryProvider)),
  name: 'restoreTodo',
);

final Provider<ReorderTodos> reorderTodosProvider = Provider<ReorderTodos>(
  (ref) => ReorderTodos(ref.watch(todoRepositoryProvider)),
  name: 'reorderTodos',
);

final Provider<ClearCompletedTodos> clearCompletedTodosProvider =
    Provider<ClearCompletedTodos>(
  (ref) => ClearCompletedTodos(ref.watch(todoRepositoryProvider)),
  name: 'clearCompletedTodos',
);

// --- State -----------------------------------------------------------------

/// The stored todo collection.
final AsyncNotifierProvider<TodoListController, List<Todo>> todoListProvider =
    AsyncNotifierProvider<TodoListController, List<Todo>>(
  TodoListController.new,
  name: 'todoList',
);

/// What the list should currently show.
final NotifierProvider<TodoFilterController, TodoFilter> todoFilterProvider =
    NotifierProvider<TodoFilterController, TodoFilter>(
  TodoFilterController.new,
  name: 'todoFilter',
);

/// The todos that should be on screen right now.
///
/// Derived state, not stored state: it recomputes whenever the collection or the
/// filter changes, so there is no way for the visible list to fall out of step
/// with either input.
final Provider<AsyncValue<List<Todo>>> visibleTodosProvider =
    Provider<AsyncValue<List<Todo>>>(
  (ref) {
    final AsyncValue<List<Todo>> todos = ref.watch(todoListProvider);
    final TodoFilter filter = ref.watch(todoFilterProvider);
    return todos.whenData(filter.apply);
  },
  name: 'visibleTodos',
);

/// Counts for the summary header, evaluated against the injected clock.
final Provider<AsyncValue<TodoStats>> todoStatsProvider =
    Provider<AsyncValue<TodoStats>>(
  (ref) {
    final DateTime now = ref.watch(clockProvider)();
    return ref.watch(todoListProvider).whenData(
          (List<Todo> todos) => TodoStats.fromTodos(todos, now),
        );
  },
  name: 'todoStats',
);

/// Focus node for the search field, so a keyboard shortcut can focus it.
///
/// Owned by the container rather than by a widget because the shortcut that
/// needs it (Ctrl+F) is registered higher up the tree than the field itself.
final Provider<FocusNode> searchFocusNodeProvider = Provider<FocusNode>(
  (ref) {
    final FocusNode node = FocusNode(debugLabel: 'todoSearch');
    ref.onDispose(node.dispose);
    return node;
  },
  name: 'searchFocusNode',
);
