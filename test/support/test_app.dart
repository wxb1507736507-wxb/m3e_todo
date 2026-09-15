import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_todo/app/app.dart';
import 'package:m3e_todo/core/storage/app_directories.dart';
import 'package:m3e_todo/core/storage/json_file_store.dart';
import 'package:m3e_todo/core/storage/storage_providers.dart';
import 'package:m3e_todo/features/categories/domain/repositories/category_repository.dart';
import 'package:m3e_todo/features/notes/domain/repositories/note_repository.dart';
import 'package:m3e_todo/features/notes/presentation/providers/note_providers.dart';
import 'package:m3e_todo/features/categories/presentation/providers/category_providers.dart';
import 'package:m3e_todo/features/habits/domain/repositories/habit_repository.dart';
import 'package:m3e_todo/features/habits/presentation/habit_permissions.dart';
import 'package:m3e_todo/features/habits/presentation/providers/habit_providers.dart';
import 'package:m3e_todo/features/settings/domain/app_settings.dart';
import 'package:m3e_todo/features/settings/presentation/settings_controller.dart';
import 'package:m3e_todo/features/timetable/domain/repositories/timetable_repository.dart';
import 'package:m3e_todo/features/timetable/presentation/providers/timetable_providers.dart';
import 'package:m3e_todo/features/todos/domain/repositories/todo_repository.dart';
import 'package:m3e_todo/features/todos/presentation/providers/todo_providers.dart';

import 'sample_todo.dart';

/// Builds the real app wired to test doubles.
///
/// Overriding the repository and the clock is enough to make almost everything
/// deterministic; only tests that care about persistence need to pass
/// [dataDirectory]. That is the payoff of keeping platform I/O out of the widget
/// tree: nothing below the container touches a real filesystem unless the test
/// explicitly asks it to.
Widget buildTestApp({
  required TodoRepository repository,
  DateTime? now,
  AppSettings settings = const AppSettings(),
  Directory? dataDirectory,
  CategoryRepository? categoryRepository,
  NoteRepository? noteRepository,
  HabitRepository? habitRepository,
  HabitPermissions? habitPermissions,
  TimetableRepository? timetableRepository,
}) {
  // Always redirected away from the real per-user directory. A test must never
  // be able to read or overwrite the developer's actual todos, and defaulting to
  // a throwaway directory means a test cannot forget to isolate itself.
  final Directory directory =
      dataDirectory ?? Directory.systemTemp.createTempSync('m3e_todo_test');

  return ProviderScope(
    overrides: [
      todoRepositoryProvider.overrideWithValue(repository),
      initialSettingsProvider.overrideWithValue(settings),
      clockProvider.overrideWithValue(() => now ?? testNow),
      documentStoreFactoryProvider.overrideWithValue(
        (String name) => JsonFileStore(directory.childFile(name)),
      ),
      // Folders are opted into per test: most tests do not care about them, and
      // the real repository reads a file, which a widget test should not wait for.
      if (categoryRepository != null)
        categoryRepositoryProvider.overrideWithValue(categoryRepository),
      if (noteRepository != null)
        noteRepositoryProvider.overrideWithValue(noteRepository),
      // Same reason as the folders: two documents behind a real filesystem, and
      // nothing in a widget test should be waiting on that.
      if (habitRepository != null)
        habitRepositoryProvider.overrideWithValue(habitRepository),
      // The permission asker is a double by default in tests, not just when
      // asked for: the real one talks to Android, and there is no Android here.
      habitPermissionsProvider.overrideWithValue(
        habitPermissions ?? const HabitPermissions(),
      ),
      // The timetable is opted into per test for the same reason: a widget test
      // that waits for the disk is a widget test that fails on a slow machine.
      if (timetableRepository != null)
        timetableRepositoryProvider.overrideWithValue(timetableRepository),
    ],
    child: const M3eTodoApp(),
  );
}
