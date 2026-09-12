import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/storage/json_file_store.dart';
import 'package:m3e_todo/features/todos/data/datasources/todo_local_data_source.dart';
import 'package:m3e_todo/features/todos/data/repositories/local_todo_repository.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo.dart';
import 'package:m3e_todo/features/todos/domain/entities/todo_priority.dart';

import '../../../support/sample_todo.dart';

void main() {
  late Directory tempDir;
  late File document;
  late LocalTodoRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('m3e_todo_test');
    document = File('${tempDir.path}${Platform.pathSeparator}todos.json');
    repository = LocalTodoRepository(
      TodoLocalDataSource(JsonFileStore(document)),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('starts empty when the file does not exist yet', () async {
    expect(await repository.loadAll(), isEmpty);
    expect(document.existsSync(), isFalse);
  });

  test('round-trips a collection through the file', () async {
    final List<Todo> todos = <Todo>[
      sampleTodo(id: 'a', title: '第一项', priority: TodoPriority.high),
      sampleTodo(id: 'b', title: '第二项', dueDate: DateTime(2026, 4, 1))
          .completeAt(DateTime(2026, 3, 20)),
    ];

    await repository.saveAll(todos);

    // A brand new repository, so the value must come off disk rather than from
    // the first instance's cache.
    final LocalTodoRepository reopened = LocalTodoRepository(
      TodoLocalDataSource(JsonFileStore(document)),
    );
    final List<Todo> restored = await reopened.loadAll();

    expect(restored, todos);
    expect(restored.first.priority, TodoPriority.high);
  });

  test('writes a versioned envelope', () async {
    await repository.saveAll(<Todo>[sampleTodo()]);
    final String raw = await document.readAsString();
    expect(raw, contains('"version"'));
    expect(raw, contains('"todos"'));
  });

  test('hands out an unmodifiable list so the cache cannot be mutated', () async {
    await repository.saveAll(<Todo>[sampleTodo()]);
    final List<Todo> loaded = await repository.loadAll();
    expect(() => loaded.add(sampleTodo(id: 'x')), throwsUnsupportedError);
  });

  test('leaves no temporary file behind after a successful write', () async {
    await repository.saveAll(<Todo>[sampleTodo()]);
    expect(File('${document.path}.tmp').existsSync(), isFalse);
  });

  test('quarantines a corrupt file and starts from empty', () async {
    await document.writeAsString('{ this is not json');

    expect(await repository.loadAll(), isEmpty);

    final List<String> leftovers = tempDir
        .listSync()
        .map((FileSystemEntity entity) => entity.path)
        .where((String path) => path.contains('.corrupt-'))
        .toList();
    expect(leftovers, hasLength(1));
  });

  test('skips an individual malformed record but keeps the good ones', () async {
    await document.writeAsString('''
{
  "version": 1,
  "todos": [
    {"id": "good", "title": "有效", "createdAt": "2026-03-01T10:00:00.000"},
    {"id": "", "title": "无效", "createdAt": "2026-03-01T10:00:00.000"},
    {"title": "缺少 id"},
    "not even an object"
  ]
}
''');

    final List<Todo> loaded = await repository.loadAll();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'good');
  });

  test('returns an empty list for a document whose todos key is the wrong type', () async {
    await document.writeAsString('{"version": 1, "todos": "oops"}');
    expect(await repository.loadAll(), isEmpty);
  });
}
