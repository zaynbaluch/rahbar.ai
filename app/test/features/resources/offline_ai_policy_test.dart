import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:bayaz_ai/features/resources/offline_ai_gate.dart';
import 'package:bayaz_ai/features/resources/offline_ai_navigation.dart';
import 'package:bayaz_ai/features/resources/offline_ai_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OfflineAiPolicy _policy(bool enabled) => OfflineAiPolicy(
      readState: () async => OnboardingState(offlineAiEnabled: enabled),
    );

void main() {
  test('requires the stored offline AI preference', () async {
    await expectLater(_policy(true).requireEnabled(), completes);
    await expectLater(
      _policy(false).requireEnabled(),
      throwsA(isA<OfflineAiDisabledException>()),
    );
  });

  testWidgets('gate does not build local-model content when disabled',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OfflineAiGate(
        title: 'Custom generation',
        policy: _policy(false),
        enabledBuilder: (_) => const Text('Model feature'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Offline AI is turned off'), findsOneWidget);
    expect(find.text('Model feature'), findsNothing);
  });

  testWidgets('gate builds local-model content when enabled', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OfflineAiGate(
        title: 'Custom generation',
        policy: _policy(true),
        enabledBuilder: (_) => const Scaffold(body: Text('Model feature')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Model feature'), findsOneWidget);
    expect(find.text('Offline AI is turned off'), findsNothing);
  });

  testWidgets('navigation blocks disabled entry points', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => openOfflineAiScreen(
              context,
              (_) => const Scaffold(body: Text('Destination')),
              policy: _policy(false),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Offline AI is turned off'), findsOneWidget);
    expect(find.text('Destination'), findsNothing);
  });

  testWidgets('navigation opens enabled entry points', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => openOfflineAiScreen(
              context,
              (_) => const Scaffold(body: Text('Destination')),
              policy: _policy(true),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Destination'), findsOneWidget);
  });
}
