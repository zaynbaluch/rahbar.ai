import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/generation_screen.dart';
import 'package:bayaz_ai/features/generation/mcq_grammar.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/generation/mcq_test_view.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:bayaz_ai/features/resources/offline_ai_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

McqTest _paper(String topic, int count) => McqTest(
  topic: topic,
  expectedCount: count,
  questions: [
    for (var i = 1; i <= count; i++)
      McqQuestion(
        number: i,
        difficulty: 'easy',
        text: 'Question $i?',
        options: const {'A': 'One', 'B': 'Two', 'C': 'Three', 'D': 'Four'},
        answer: 'A',
      ),
  ],
);

void main() {
  test('grammar is generated for the requested supported count', () {
    final five = mcqGrammarForCount(5);
    final fifteen = mcqGrammarForCount(15);
    expect(five, contains('block5'));
    expect(five, isNot(contains('block6 ::=')));
    expect(fifteen, contains('block15'));
    expect(fifteen, contains('15='));
  });

  testWidgets('custom test route selects 5 10 or 15 and converges to viewer', (
    tester,
  ) async {
    var requested = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GenerationScreen(
          initialKind: 'mcq',
          dedicated: true,
          teachingContext: const TeachingContext(
            className: 'Class 6',
            subjectName: 'Science',
          ),
          offlineAiPolicy: OfflineAiPolicy(
            readState: () async =>
                const OnboardingState(offlineAiEnabled: true),
          ),
          generateTestOverride: (topic, count) async {
            requested = count;
            return _paper(topic, count);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Volcanoes');
    await tester.tap(find.text('15'));
    await tester.tap(find.text('Create test'));
    await tester.pumpAndSettle();

    expect(requested, 15);
    expect(find.byType(McqTestScreen), findsOneWidget);
    expect(find.text('15 questions'), findsOneWidget);
  });
}
