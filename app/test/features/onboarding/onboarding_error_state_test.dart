import 'package:bayaz_ai/features/onboarding/onboarding_gate.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingStore extends OnboardingStore {
  var fail = true;
  var resetCalls = 0;

  @override
  Future<OnboardingState> read() async {
    if (fail) throw StateError('storage unavailable');
    return const OnboardingState();
  }

  @override
  Future<void> reset() async {
    resetCalls++;
    fail = false;
  }
}

void main() {
  testWidgets('startup shows retry and reset instead of spinning forever', (
    tester,
  ) async {
    final store = _FailingStore();
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingGate(
          store: store,
          inspectAi: () async => null,
          child: const Text('App'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Bayaz could not read setup data on this device.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Reset setup'), findsOneWidget);

    await tester.tap(find.text('Reset setup'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.resetCalls, 1);
    expect(find.text('Welcome to Bayaz'), findsOneWidget);
  });
}
