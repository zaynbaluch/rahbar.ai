import 'package:bayaz_ai/features/content/content_service.dart';
import 'package:bayaz_ai/features/content/topic_picker_screen.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/lesson_plan.dart';
import 'package:bayaz_ai/features/generation/lesson_plan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Content extends ContentService {
  final topics = const [
    Topic(
      id: 'cells',
      chapter: 2,
      sectionNo: '2.1',
      title: 'Cells',
      summary: 'Basic unit of life',
      slos: ['Identify a cell.'],
      nItems: 12,
    ),
  ];

  @override
  Future<void> init() async {}

  @override
  List<Topic> listTopics() => topics;

  @override
  LessonPlan assemblePlan(String topicId, {Map<String, String> prefer = const {}, int? seed}) =>
      const LessonPlan(
        topicId: 'cells',
        topic: 'Cells',
        slos: ['Identify a cell.'],
        sections: [
          PlanSection(id: 'engage-1', section: 'engage', variantLabel: 'one', minutes: 5, body: 'Ask what living things are made of.'),
        ],
      );

  @override
  Map<String, List<PlanSection>> variantsFor(String topicId) => const {};

  @override
  void dispose() {}
}

const _context = TeachingContext(
  classCode: '6',
  className: 'Class 6',
  subjectCode: 'general_science',
  subjectName: 'General Science',
);

void main() {
  testWidgets('lesson picker is focused and opens a lesson directly', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TopicPickerScreen(
        mode: TopicPickerMode.lesson,
        teachingContext: _context,
        content: _Content(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Prepare Lesson'), findsOneWidget);
    expect(find.text('Cells'), findsOneWidget);
    expect(find.text('Create a custom lesson'), findsOneWidget);
    expect(find.textContaining('verified offline'), findsNothing);
    expect(find.textContaining('Continue your work'), findsNothing);
    expect(find.textContaining('questions available'), findsNothing);

    await tester.tap(find.text('Cells'));
    await tester.pumpAndSettle();

    expect(find.byType(LessonPlanScreen), findsOneWidget);
  });

  testWidgets('ambiguous workflow context is shown with Change', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TopicPickerScreen(
        mode: TopicPickerMode.lesson,
        teachingContext: _context,
        showContextChange: true,
        content: _Content(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Class 6 · General Science'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('no-match lesson search offers the custom lesson with query carried', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TopicPickerScreen(
        mode: TopicPickerMode.lesson,
        teachingContext: _context,
        content: _Content(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Volcanoes');
    await tester.pump();

    expect(find.text('Create a custom lesson'), findsOneWidget);
  });
}
