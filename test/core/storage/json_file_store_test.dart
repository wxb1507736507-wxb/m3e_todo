import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/core/storage/json_file_store.dart';

void main() {
  late Directory tempDir;
  late File document;
  late JsonFileStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('m3e_todo_store');
    document = File('${tempDir.path}${Platform.pathSeparator}doc.json');
    store = JsonFileStore(document);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('writes and reads a document', () async {
    await store.write(<String, Object?>{'n': 1});
    expect((await store.read())!['n'], 1);
  });

  test('read returns null when nothing was written', () async {
    expect(await store.read(), isNull);
  });

  test('overwrites a previous document', () async {
    await store.write(<String, Object?>{'n': 1});
    await store.write(<String, Object?>{'n': 2});
    expect((await store.read())!['n'], 2);
  });

  test('serialises concurrent writes so the last one wins', () async {
    // Regression test. Every write shares one `.tmp` path, so before writes were
    // chained this threw PathNotFoundException (the temp file had already been
    // renamed away) or a sharing violation on Windows, and the document kept a
    // stale value. The settings controller writes fire-and-forget, so
    // overlapping writes are the normal case rather than an edge case.
    await Future.wait(<Future<void>>[
      for (int i = 0; i < 24; i++) store.write(<String, Object?>{'n': i}),
    ]);

    expect((await store.read())!['n'], 23);
    expect(File('${document.path}.tmp').existsSync(), isFalse);
  });

  test('a failed write does not poison later ones', () async {
    // An unserialisable value makes the encoder throw before any file work.
    await expectLater(
      store.write(<String, Object?>{'bad': Object()}),
      throwsA(anything),
    );

    await store.write(<String, Object?>{'ok': true});

    expect((await store.read())!['ok'], isTrue);
  });

  test('creates the parent directory on demand', () async {
    final JsonFileStore nested = JsonFileStore(
      File(
        '${tempDir.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}deep.json',
      ),
    );

    await nested.write(<String, Object?>{'n': 1});

    expect((await nested.read())!['n'], 1);
  });

  test('delete removes the document and any leftover temp file', () async {
    await store.write(<String, Object?>{'n': 1});
    final File temp = File('${document.path}.tmp');
    await temp.writeAsString('leftover');

    await store.delete();

    expect(document.existsSync(), isFalse);
    expect(temp.existsSync(), isFalse);
  });
}
