import 'dart:async';

import 'package:bayaz_ai/features/generation/local_ai_route_lifecycle.dart';
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
}
