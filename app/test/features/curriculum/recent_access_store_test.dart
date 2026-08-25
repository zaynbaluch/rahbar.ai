import 'dart:io';

import 'package:bayaz_ai/features/curriculum/recent_access_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  late int clock;
  late RecentAccessStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bayaz-recents-');
    file = File('${directory.path}/recent.json');
    clock = 1000;
    store = RecentAccessStore(
      fileProvider: () async => file,
      nowMillis: () => clock++,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('keeps concurrent updates instead of losing earlier items', () async {
    await Future.wait([
      for (var index = 0; index < 8; index++)
        store.record(
          classCode: '6',
          subjectCode: 'science',
          topicId: 'topic-$index',
          topicTitle: 'Topic $index',
        ),
    ]);

    final items = await store.list();
    expect(items, hasLength(8));
    expect(items.map((item) => item.topicId).toSet(), {
      for (var index = 0; index < 8; index++) 'topic-$index',
    });
  });

  test('moves an existing topic to the front without duplicating it', () async {
    await store.record(
      classCode: '6',
      subjectCode: 'science',
      topicId: 'plants',
      topicTitle: 'Plants',
    );
    await store.record(
      classCode: '6',
      subjectCode: 'science',
      topicId: 'energy',
      topicTitle: 'Energy',
    );
    await store.record(
      classCode: '6',
      subjectCode: 'science',
      topicId: 'plants',
      topicTitle: 'Plant life',
    );

    final items = await store.list();
    expect(items.map((item) => item.topicId), ['plants', 'energy']);
    expect(items.first.topicTitle, 'Plant life');
  });

  test('quarantines malformed recent data', () async {
    await file.writeAsString('{not json', flush: true);

    expect(await store.list(), isEmpty);
    expect(await file.exists(), isFalse);
    expect(
      await directory.list().where((entry) => entry.path.contains('.corrupt.')).length,
      1,
    );
  });
}
