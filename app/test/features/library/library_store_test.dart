import 'dart:convert';
import 'dart:io';

import 'package:bayaz_ai/features/library/library_store.dart';
import 'package:bayaz_ai/features/library/saved_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library_store_test.');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('reports unreadable saved items while keeping valid items', () async {
    final store = LibraryStore(supportDirectory: () async => root);
    final library = Directory('${root.path}/library');
    await library.create(recursive: true);
    await File('${library.path}/good.json').writeAsString(jsonEncode(
      const SavedTest(
        id: 'good',
        kind: 'lesson',
        topic: 'Matter',
        createdAtMillis: 10,
      ).toJson(),
    ));
    await File('${library.path}/bad.json').writeAsString('{not json');

    final result = await store.load();

    expect(result.items.map((item) => item.id), ['good']);
    expect(result.recoveredFiles, 1);
    expect(await File('${library.path}/bad.json').exists(), isFalse);
    expect(
      await library
          .list()
          .where((entry) => entry.path.contains('bad.json.corrupt.'))
          .length,
      1,
    );
  });
}
