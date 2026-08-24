import 'dart:async';

import 'package:bayaz_ai/features/rag/embedding_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns a successful embedding without resetting', () async {
    var resets = 0;
    final result = await const EmbeddingRequestRunner().run(
      request: () async => [1, 2, 3],
      reset: () async => resets++,
    );

    expect(result, [1, 2, 3]);
    expect(resets, 0);
  });

  test('resets the session when an embedding request fails', () async {
    var resets = 0;

    await expectLater(
      const EmbeddingRequestRunner().run(
        request: () async => throw StateError('native failure'),
        reset: () async => resets++,
      ),
      throwsA(isA<LocalEmbeddingException>()),
    );
    expect(resets, 1);
  });

  test('times out and resets a stuck embedding request', () async {
    var resets = 0;
    final never = Completer<List<double>>();

    await expectLater(
      const EmbeddingRequestRunner(timeout: Duration(milliseconds: 1)).run(
        request: () => never.future,
        reset: () async => resets++,
      ),
      throwsA(
        isA<LocalEmbeddingException>().having(
          (error) => error.message,
          'message',
          contains('took too long'),
        ),
      ),
    );
    expect(resets, 1);
  });

  test('keeps the request error when reset also fails', () async {
    await expectLater(
      const EmbeddingRequestRunner().run(
        request: () async => throw StateError('request failed'),
        reset: () async => throw StateError('reset failed'),
      ),
      throwsA(
        isA<LocalEmbeddingException>().having(
          (error) => error.cause.toString(),
          'cause',
          contains('request failed'),
        ),
      ),
    );
  });
}
