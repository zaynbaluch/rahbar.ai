import 'dart:async';

import 'package:bayaz_ai/features/generation/local_ai_route_lifecycle.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalidates older operation tokens', () {
    final lifecycle = LocalAiRouteLifecycle();
    final first = lifecycle.beginOperation();
    final second = lifecycle.beginOperation();

    expect(lifecycle.isCurrent(first), isFalse);
    expect(lifecycle.isCurrent(second), isTrue);
  });

  test('closing invalidates callbacks and runs cleanup once', () async {
    final lifecycle = LocalAiRouteLifecycle();
    final token = lifecycle.beginOperation();
    final cleanup = Completer<void>();
    var calls = 0;

    final firstClose = lifecycle.close(() {
      calls++;
      return cleanup.future;
    });
    final secondClose = lifecycle.close(() async => calls++);

    expect(lifecycle.closing, isTrue);
    expect(lifecycle.isCurrent(token), isFalse);
    expect(calls, 1);
    cleanup.complete();
    await Future.wait([firstClose, secondClose]);
    expect(calls, 1);
  });

  test('a later close replays the cached cleanup failure without retrying',
      () async {
    final lifecycle = LocalAiRouteLifecycle();
    final failure = StateError('unload failed');
    var calls = 0;

    final firstClose = lifecycle.close(() async {
      calls++;
      throw failure;
    });

    expect(lifecycle.closing, isTrue);
    await expectLater(firstClose, throwsA(same(failure)));

    final secondClose = lifecycle.close(() async => calls++);
    await expectLater(secondClose, throwsA(same(failure)));
    expect(lifecycle.closing, isTrue);
    expect(calls, 1);
  });

  testWidgets('a failing cleanup is reported and the route still pops',
      (tester) async {
    await tester.pumpWidget(const SizedBox());

    final reported = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    final failure = StateError('unload failed');
    final calls = <String>[];
    var finished = false;

    final done = finishLocalAiRouteClose(
      Future<void>.error(failure),
      description: 'closing the test route',
      isMounted: () => true,
      allowPop: () => calls.add('allowPop'),
      pop: () => calls.add('pop'),
    ).then((_) => finished = true);

    for (var i = 0; i < 5 && !finished; i++) {
      await tester.pump();
    }
    await done;

    expect(finished, isTrue);
    expect(calls, ['allowPop', 'pop']);
    expect(reported, hasLength(1));
    expect(reported.single.exception, same(failure));
  });

  testWidgets('an unmounted screen is never popped', (tester) async {
    await tester.pumpWidget(const SizedBox());

    final calls = <String>[];
    await finishLocalAiRouteClose(
      Future<void>.value(),
      description: 'closing the test route',
      isMounted: () => false,
      allowPop: () => calls.add('allowPop'),
      pop: () => calls.add('pop'),
    );

    expect(calls, isEmpty);
  });
}
