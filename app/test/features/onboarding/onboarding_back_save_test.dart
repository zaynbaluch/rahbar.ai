import 'package:bayaz_ai/features/onboarding/onboarding_screen.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingStore extends OnboardingStore {
  OnboardingState state = const OnboardingState(completed: true);
  final saved = <OnboardingState>[];

  @override
  Future<OnboardingState> read() async => state;

  @override
  Future<void> save(OnboardingState next) async {
    saved.add(next);
    state = next;
  }
}

Widget _host(_RecordingStore store) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OnboardingScreen(
                reconfigure: true,
                store: store,
                inspectAi: () async => null,
              ),
            )),
            child: const Text('Open setup'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('back saves the latest reconfiguration text', (tester) async {
    final store = _RecordingStore();
    await tester.pumpWidget(_host(store));

    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Ayesha Khan',
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Open setup'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(store.state.teacherName, 'Ayesha Khan');
    expect(store.saved, hasLength(1));
    expect(store.saved.single.teacherName, 'Ayesha Khan');
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('finishing reconfiguration saves once and closes the route',
      (tester) async {
    final store = _RecordingStore();
    await tester.pumpWidget(_host(store));

    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ayesha Khan');
    await tester.enterText(find.byType(TextField).at(1), 'Model School');

    // Reconfiguration reopens at the first step, so walk to the final one.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Finish'), findsOneWidget);

    store.saved.clear();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Open setup'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(store.saved, hasLength(1));
    expect(store.saved.single.teacherName, 'Ayesha Khan');
    expect(store.saved.single.schoolName, 'Model School');
    expect(store.saved.single.completed, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
