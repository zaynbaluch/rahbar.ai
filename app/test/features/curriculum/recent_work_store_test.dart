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

  test('recent reference and active grading persist independently', () async {
    final store = RecentWorkStore(fileProvider: () async => file);
    await store.update(
      const RecentWorkReference(type: 'lesson', id: 'lesson-1'),
    );
    await store.setActiveGrading('test-1');

    final reopened = RecentWorkStore(fileProvider: () async => file);
    expect((await reopened.current())?.id, 'lesson-1');
    expect(await reopened.activeGradingTestId(), 'test-1');

    await reopened.clearActiveGrading();
    expect(await reopened.activeGradingTestId(), isNull);
    expect((await reopened.current())?.id, 'lesson-1');
  });

  test(
    'invalidating a target clears matching active and recent references',
    () async {
      final store = RecentWorkStore(fileProvider: () async => file);
      await store.update(const RecentWorkReference(type: 'test', id: 'test-1'));
      await store.setActiveGrading('test-1');
      await store.invalidateTarget('test-1');
      expect(await store.current(), isNull);
      expect(await store.activeGradingTestId(), isNull);
    },
  );

  test('clear removes all recent workflow state', () async {
    final store = RecentWorkStore(fileProvider: () async => file);
    await store.update(
      const RecentWorkReference(type: 'lesson', id: 'lesson-1'),
    );
    await store.setActiveGrading('test-1');
    await store.clear();
    expect(await store.current(), isNull);
    expect(await store.activeGradingTestId(), isNull);
  });
}
