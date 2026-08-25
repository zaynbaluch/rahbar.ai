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
  LessonPlan assemblePlan(
    String topicId, {
    Map<String, String> prefer = const {},
    int? seed,
  }) => const LessonPlan(
    topicId: 'cells',
    topic: 'Cells',
    slos: ['Identify a cell.'],
    sections: [
      PlanSection(
        id: 'engage-1',
        section: 'engage',
        variantLabel: 'one',
        minutes: 5,
        body: 'Ask what living things are made of.',
      ),
    ],
  );

  @override
  Map<String, List<PlanSection>> variantsFor(String topicId) => const {};

  @override
  void dispose() {}
}

class _GroupedContent extends _Content {
  @override
  final topics = const [
    Topic(
      id: 'cells',
      chapter: 1,
      sectionNo: '1.1',
      title: 'Cells',
      summary: '',
      slos: [],
      nItems: 12,
    ),
    Topic(
      id: 'organelles',
      chapter: 1,
      sectionNo: '1.1.1',
      title: 'Cell Organelles',
      summary: '',
      slos: [],
      nItems: 12,
    ),
    Topic(
      id: 'reproduction',
      chapter: 2,
      sectionNo: '2.1',
      title: 'Reproduction',
      summary: '',
      slos: [],
      nItems: 12,
    ),
    Topic(
      id: 'sexual',
      chapter: 2,
      sectionNo: '2.1.1',
      title: 'Sexual Reproduction in Plants',
      summary: '',
      slos: [],
      nItems: 12,
    ),
  ];
}

const _context = TeachingContext(
  classCode: '6',
  className: 'Class 6',
  subjectCode: 'general_science',
  subjectName: 'General Science',
);

void main() {
  testWidgets('lesson picker is focused and opens a lesson directly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TopicPickerScreen(
          mode: TopicPickerMode.lesson,
          teachingContext: _context,
          content: _Content(),
        ),
      ),
    );
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

  testWidgets('ambiguous workflow context is shown with Change', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TopicPickerScreen(
          mode: TopicPickerMode.lesson,
          teachingContext: _context,
          showContextChange: true,
          content: _Content(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Class 6 · General Science'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets(
    'curriculum test topic opens count-only setup with verified limits',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TopicPickerScreen(
            mode: TopicPickerMode.test,
            teachingContext: _context,
            content: _Content(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cells'));
      await tester.pumpAndSettle();

      expect(find.text('Number of questions'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('Create test'), findsOneWidget);
      expect(find.textContaining('difficulty'), findsNothing);
      final fifteen = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '15'),
      );
      expect(fifteen.onSelected, isNull);
      final ten = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '10'),
      );
      expect(ten.selected, isTrue);
    },
  );

  test('curriculum test counts never exceed verified availability', () {
    expect(availableTestCounts(16), [5, 10, 15]);
    expect(availableTestCounts(12), [5, 10]);
    expect(availableTestCounts(7), [5]);
    expect(availableTestCounts(4), isEmpty);
    expect(defaultTestCount(12), 10);
    expect(defaultTestCount(7), 5);
    expect(defaultTestCount(4), isNull);
  });

  testWidgets(
    'no-match lesson search offers the custom lesson with query carried',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TopicPickerScreen(
            mode: TopicPickerMode.lesson,
            teachingContext: _context,
            content: _Content(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Volcanoes');
      await tester.pump();

      expect(find.text('Create a custom lesson'), findsOneWidget);
    },
  );

  testWidgets('topics are grouped into collapsible chapter sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TopicPickerScreen(
          mode: TopicPickerMode.test,
          teachingContext: _context,
          content: _GroupedContent(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chapter 1 · Cells'), findsOneWidget);
    expect(find.text('Chapter 2 · Reproduction'), findsOneWidget);
    expect(find.text('Cell Organelles'), findsOneWidget);
    expect(find.text('Sexual Reproduction in Plants'), findsNothing);
    await tester.tap(find.text('Chapter 2 · Reproduction'));
    await tester.pumpAndSettle();
    expect(find.text('Sexual Reproduction in Plants'), findsOneWidget);
  });

  testWidgets('test setup keeps the create action at the bottom', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TopicPickerScreen(
          mode: TopicPickerMode.test,
          teachingContext: _context,
          content: _Content(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cells'));
    await tester.pumpAndSettle();
    final setupScaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(setupScaffold.bottomNavigationBar, isNotNull);
  });
}
