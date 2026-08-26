import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/generation_screen.dart';
import 'package:bayaz_ai/features/generation/lesson_plan.dart';
import 'package:bayaz_ai/features/generation/lesson_plan_view.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:bayaz_ai/features/resources/offline_ai_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('custom lesson route is dedicated and converges to lesson viewer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GenerationScreen(
        initialKind: 'lesson',
        dedicated: true,
        teachingContext: const TeachingContext(className: 'Class 6', subjectName: 'General Science'),
        offlineAiPolicy: OfflineAiPolicy(readState: () async => const OnboardingState(offlineAiEnabled: true)),
        generateLessonOverride: (topic) async => LessonPlan(
          topicId: 'custom',
          topic: topic,
          slos: const ['Explain the topic.'],
          sections: const [PlanSection(id: 'one', section: 'engage', variantLabel: '', minutes: 5, body: 'Start here.')],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.textContaining('RAG'), findsNothing);
    expect(find.textContaining('grounding'), findsNothing);
    expect(find.text('Create lesson'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Volcanoes');
    await tester.tap(find.text('Create lesson'));
    await tester.pumpAndSettle();

    expect(find.byType(LessonPlanScreen), findsOneWidget);
    expect(find.text('Volcanoes'), findsWidgets);
  });
}
