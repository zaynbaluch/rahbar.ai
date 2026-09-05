import 'package:bayaz_ai/features/chat/clarification_context.dart';
import 'package:bayaz_ai/features/chat/clarification_screen.dart';
import 'package:bayaz_ai/features/generation/lesson_plan.dart';
import 'package:bayaz_ai/features/resources/offline_ai_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _plan = LessonPlan(
  topicId: 'cells',
  topic: 'Cells',
  slos: ['Identify parts of a cell.'],
  sections: [
    PlanSection(
      id: 'e',
      section: 'engage',
      variantLabel: '',
      minutes: 5,
      body: 'Look at cells.',
    ),
  ],
);

void main() {
  testWidgets('contextual chat is quiet and shows three tappable suggestions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClarificationScreen(
          contextMaterial: ClarificationContext.lesson(_plan),
          offlineAiPolicy: OfflineAiPolicy(
            readState: () async => throw UnimplementedError(),
          ),
          policyEnabledOverride: () async => true,
          readinessOverride: () async => true,
          answerOverride: (q) async => 'A classroom-ready answer.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ask Bayaz'), findsOneWidget);
    expect(find.text('Cells · Lesson Plan'), findsOneWidget);
    expect(find.byKey(const Key('ask-bayaz-suggestion')), findsNWidgets(3));
    expect(find.textContaining('Curriculum-grounded'), findsNothing);
    expect(find.textContaining('Ungrounded'), findsNothing);
    expect(find.textContaining('Clarify '), findsNothing);

    final first = find.byKey(const Key('ask-bayaz-suggestion')).first;
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(find.text('A classroom-ready answer.'), findsOneWidget);
  });

  testWidgets('not ready state avoids model internals', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ClarificationScreen(
          contextMaterial: ClarificationContext.lesson(_plan),
          policyEnabledOverride: () async => true,
          readinessOverride: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bayaz is still getting ready.'), findsOneWidget);
    expect(find.textContaining('model'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('View Offline AI'), findsOneWidget);
  });
}
