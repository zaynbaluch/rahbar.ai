import 'package:bayaz_ai/features/generation/local_model_handoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('releases models in a safe order around retrieval', () async {
    final calls = <String>[];

    final result = await const LocalModelHandoff().retrieve(
      releaseGenerator: () async => calls.add('release generator'),
      runRetrieval: () async {
        calls.add('retrieve');
        return 'context';
      },
      releaseRetriever: () async => calls.add('release retriever'),
    );

    expect(result, 'context');
    expect(calls, [
      'release generator',
      'retrieve',
      'release retriever',
    ]);
  });

  test('still releases the retriever when retrieval fails', () async {
    final calls = <String>[];

    await expectLater(
      const LocalModelHandoff().retrieve<void>(
        releaseGenerator: () async => calls.add('release generator'),
        runRetrieval: () async {
          calls.add('retrieve');
          throw StateError('failed');
        },
        releaseRetriever: () async => calls.add('release retriever'),
      ),
      throwsStateError,
    );
    expect(calls, [
      'release generator',
      'retrieve',
      'release retriever',
    ]);
  });
}
