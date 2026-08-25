import 'dart:io';

import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/omr/image_pick_recovery.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class _LostData implements LostImageDataProvider {
  _LostData(this.value);
  final LostImageData value;
  var calls = 0;

  @override
  Future<LostImageData> retrieve() async {
    calls++;
    return value;
  }
}

McqTest _test() => McqTest(
      id: 'paper-1',
      topic: 'Plants',
      expectedCount: 1,
      questions: const [
        McqQuestion(
          number: 1,
          text: 'What do leaves use?',
          options: {'A': 'Light', 'B': 'Stone', 'C': 'Metal', 'D': 'Glass'},
          answer: 'A',
          difficulty: 'easy',
        ),
      ],
    );

void main() {
  late Directory directory;
  late File stateFile;
  late PendingImagePickStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bayaz-picker-recovery-');
    stateFile = File('${directory.path}/pending.json');
    store = PendingImagePickStore(
      fileProvider: () async => stateFile,
      nowMillis: () => 1000,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('persists the full paper before picker launch', () async {
    await store.begin(_test(), ImageSource.camera);

    final pending = await store.read();
    expect(pending, isNotNull);
    expect(pending!.test.id, 'paper-1');
    expect(pending.source, 'camera');
  });

  test('copies a lost camera image into permanent support storage', () async {
    final source = File('${directory.path}/cache-photo.jpg');
    await source.writeAsBytes([1, 2, 3], flush: true);
    await store.begin(_test(), ImageSource.camera);
    final lost = _LostData(LostImageData(paths: [source.path]));
    final service = ImagePickRecoveryService(
      store: store,
      lostData: lost,
      supportDirectory: () async => directory,
      nowMillis: () => 1100,
    );

    final recovered = await service.recover();

    expect(recovered, isNotNull);
    expect(recovered!.test.id, 'paper-1');
    expect(await File(recovered.imagePath).readAsBytes(), [1, 2, 3]);
    expect((await store.read())!.recoveredImagePath, recovered.imagePath);
  });

  test('clears pending state when Android has no lost result', () async {
    await store.begin(_test(), ImageSource.gallery);
    final service = ImagePickRecoveryService(
      store: store,
      lostData: _LostData(const LostImageData()),
      supportDirectory: () async => directory,
      nowMillis: () => 1100,
    );

    expect(await service.recover(), isNull);
    expect(await store.read(), isNull);
  });

  test('reuses a previously copied recovery image after another restart', () async {
    final recoveredFile = File('${directory.path}/recovered.jpg');
    await recoveredFile.writeAsBytes([9], flush: true);
    await store.save(PendingImagePick(
      test: _test(),
      source: 'camera',
      createdAtMillis: 1000,
      recoveredImagePath: recoveredFile.path,
    ));
    final lost = _LostData(const LostImageData());
    final service = ImagePickRecoveryService(
      store: store,
      lostData: lost,
      supportDirectory: () async => directory,
      nowMillis: () => 1100,
    );

    final recovered = await service.recover();

    expect(recovered?.imagePath, recoveredFile.path);
    expect(lost.calls, 1);
  });

  test('expires stale pending requests', () async {
    await store.begin(_test(), ImageSource.camera);
    final service = ImagePickRecoveryService(
      store: store,
      lostData: _LostData(const LostImageData()),
      supportDirectory: () async => directory,
      nowMillis: () => const Duration(hours: 25).inMilliseconds + 1000,
    );

    expect(await service.recover(), isNull);
    expect(await store.read(), isNull);
  });

  test('pending image pick preserves teaching context', () async {
    const context = TeachingContext(classCode: '6', className: 'Class 6', subjectCode: 'science', subjectName: 'Science');
    await store.begin(_test(), ImageSource.camera, teachingContext: context);
    final pending = await store.read();
    expect(pending?.teachingContext?.subjectName, 'Science');
  });
}
