import 'dart:convert';
import 'dart:io';

import 'package:bayaz_ai/features/omr/gradebook_store.dart';
import 'package:bayaz_ai/features/omr/graded_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gradebook_store_test.');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('reports unreadable results while keeping valid results', () async {
    final store = GradebookStore(supportDirectory: () async => root);
    final gradebook = Directory('${root.path}/gradebook');
    await gradebook.create(recursive: true);
    await File('${gradebook.path}/good.json').writeAsString(jsonEncode(
      const GradedResult(
        id: 'good',
        testId: 'paper',
        testTopic: 'Matter',
        studentName: 'Student 1',
        correct: 1,
        total: 1,
        marks: 'A',
        correctAnswers: 'A',
        createdAtMillis: 10,
      ).toJson(),
    ));
    await File('${gradebook.path}/bad.json').writeAsString('[]');

    final result = await store.loadForTest('paper');

    expect(result.items.map((item) => item.id), ['good']);
    expect(result.recoveredFiles, 1);
    expect(await File('${gradebook.path}/bad.json').exists(), isFalse);
    expect(
      await gradebook
          .list()
          .where((entry) => entry.path.contains('bad.json.corrupt.'))
          .length,
      1,
    );
  });
}
