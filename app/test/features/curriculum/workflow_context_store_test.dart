import 'dart:io';

import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/curriculum/workflow_context_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late File file;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workflow-context-');
    file = File('${temp.path}/workflow.json');
  });
  tearDown(() async => temp.delete(recursive: true));

  test('lesson and test contexts persist independently', () async {
    final store = WorkflowContextStore(fileProvider: () async => file);
    const lesson = TeachingContext(classCode: '6', className: 'Class 6', subjectCode: 'science', subjectName: 'Science');
    const testContext = TeachingContext(classCode: '7', className: 'Class 7', subjectCode: 'math', subjectName: 'Math');
    await store.save('lesson', lesson);
    await store.save('test', testContext);

    final reopened = WorkflowContextStore(fileProvider: () async => file);
    expect((await reopened.lastFor('lesson'))?.subjectCode, 'science');
    expect((await reopened.lastFor('test'))?.classCode, '7');
  });
}
