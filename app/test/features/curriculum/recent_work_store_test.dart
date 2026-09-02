import 'dart:io';

import 'package:bayaz_ai/features/curriculum/recent_work_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late File file;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('recent-work-');
    file = File('${temp.path}/recent.json');
  });
  tearDown(() async => temp.delete(recursive: true));

  test('recent reference persists and can be cleared', () async {
    final store = RecentWorkStore(fileProvider: () async => file);
    await store.update(
      const RecentWorkReference(type: 'lesson', id: 'lesson-1'),
    );
    final reopened = RecentWorkStore(fileProvider: () async => file);
    expect((await reopened.current())?.id, 'lesson-1');
    await reopened.clear();
    expect(await reopened.current(), isNull);
  });
}
