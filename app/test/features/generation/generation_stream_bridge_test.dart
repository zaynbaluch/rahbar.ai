import 'dart:async';

import 'package:bayaz_ai/features/generation/generation_stream_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closes after the matching prompt succeeds', () async {
    final tokens = StreamController<String>.broadcast();
    final completions = StreamController<ModelCompletion>.broadcast();
    final values = <String>[];

    final done = const GenerationStreamBridge()
        .run(
          tokens: tokens.stream,
          completions: completions.stream,
          start: () async => 'prompt-1',
          stop: () async {},
        )
        .listen(values.add)
        .asFuture<void>();

    await Future<void>.delayed(Duration.zero);
    tokens.add('one');
    completions.add(const ModelCompletion(
      promptId: 'another-prompt',
      success: false,
      errorDetails: 'ignore me',
    ));
    tokens.add(' two');
    completions.add(const ModelCompletion(
      promptId: 'prompt-1',
      success: true,
    ));

    await done;
    expect(values.join(), 'one two');
    await tokens.close();
    await completions.close();
  });

  test('surfaces a failed completion instead of closing successfully', () async {
    final tokens = StreamController<String>.broadcast();
    final completions = StreamController<ModelCompletion>.broadcast();
    final stream = const GenerationStreamBridge().run(
      tokens: tokens.stream,
      completions: completions.stream,
      start: () async => 'prompt-1',
      stop: () async {},
    );

    final expectation = expectLater(
      stream,
      emitsInOrder([
        'partial',
        emitsError(
          isA<LocalGenerationException>().having(
            (error) => error.details,
            'details',
            'native failure',
          ),
        ),
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    tokens.add('partial');
    completions.add(const ModelCompletion(
      promptId: 'prompt-1',
      success: false,
      errorDetails: 'native failure',
    ));

    await expectation;
    await tokens.close();
    await completions.close();
  });

  test('handles completion that arrives before start returns', () async {
    final tokens = StreamController<String>.broadcast();
    final completions = StreamController<ModelCompletion>.broadcast();
    final startCompleter = Completer<String>();

    final done = const GenerationStreamBridge()
        .run(
          tokens: tokens.stream,
          completions: completions.stream,
          start: () => startCompleter.future,
          stop: () async {},
        )
        .drain<void>();

    await Future<void>.delayed(Duration.zero);
    completions.add(const ModelCompletion(
      promptId: 'prompt-1',
      success: true,
    ));
    startCompleter.complete('prompt-1');

    await done;
    await tokens.close();
    await completions.close();
  });

  test('stops native generation when the listener cancels', () async {
    final tokens = StreamController<String>.broadcast();
    final completions = StreamController<ModelCompletion>.broadcast();
    var stopCalls = 0;

    final subscription = const GenerationStreamBridge()
        .run(
          tokens: tokens.stream,
          completions: completions.stream,
          start: () async => 'prompt-1',
          stop: () async => stopCalls++,
        )
        .listen((_) {});

    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(stopCalls, 1);
    await tokens.close();
    await completions.close();
  });
}
