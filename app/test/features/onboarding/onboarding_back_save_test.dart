import 'package:bayaz_ai/features/onboarding/onboarding_screen.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingStore extends OnboardingStore {
  OnboardingState state = const OnboardingState(completed: true);

  @override
  Future<OnboardingState> read() async => state;

  @override
  Future<void> save(OnboardingState next) async {
    state = next;
  }
}

void main() {
  testWidgets('back saves the latest reconfiguration text', (tester) async {
    final store = _RecordingStore();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OnboardingScreen(
                reconfigure: true,
                store: store,
              ),
            )),
            child: const Text('Open setup'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Ayesha Khan',
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Open setup'), findsOneWidget);
    expect(store.state.teacherName, 'Ayesha Khan');
  });
}
