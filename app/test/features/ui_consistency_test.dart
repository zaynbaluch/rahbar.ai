import 'package:bayaz_ai/features/curriculum/curriculum_home_screen.dart';
import 'package:bayaz_ai/features/generation/lesson_plan.dart';
import 'package:bayaz_ai/features/generation/lesson_plan_view.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/generation/mcq_test_view.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends OnboardingStore {
  @override
  Future<OnboardingState> read() async =>
      const OnboardingState(completed: true, teacherName: 'Ayesha');
}

const _plan = LessonPlan(
  topicId: 'cells',
  topic: 'Cells and their functions',
  slos: [
    'Identify the main parts of a cell and explain their basic functions.',
  ],
  sections: [
    PlanSection(
      id: 'engage',
      section: 'engage',
      variantLabel: '',
      minutes: 5,
      body:
          'Ask students to compare a classroom to a cell and discuss how different parts have different jobs.',
      materials: ['chalk and board'],
    ),
  ],
);

McqTest _test() => McqTest(
  id: 'paper',
  topic: 'Cells and their functions',
  expectedCount: 5,
  questions: List.generate(
    5,
    (index) => McqQuestion(
      number: index + 1,
      difficulty: 'medium',
      text: 'Which statement best explains the function of this cell part?',
      options: const {
        'A': 'A reasonably long classroom answer',
        'B': 'Another reasonably long classroom answer',
        'C': 'A third reasonably long classroom answer',
        'D': 'A fourth reasonably long classroom answer',
      },
      answer: 'A',
    ),
  ),
);

Future<void> _compact(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('Home remains usable at compact width and large text', (
    tester,
  ) async {
    await _compact(tester);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: MaterialApp(
          home: CurriculumHomeScreen(
            onboardingStore: _Store(),
            onGradePapers: () {},
            onContinueRecent: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Prepare Lesson'), findsOneWidget);
    expect(find.text('Create Test'), findsOneWidget);
  });

  testWidgets('lesson viewer has no compact large-text overflow', (
    tester,
  ) async {
    await _compact(tester);
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: MaterialApp(home: LessonPlanReadOnlyScreen(plan: _plan)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('test viewer has no compact large-text overflow', (tester) async {
    await _compact(tester);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: MaterialApp(home: McqTestScreen(test: _test(), saved: true)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
