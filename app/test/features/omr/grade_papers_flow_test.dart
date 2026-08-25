import 'package:bayaz_ai/core/storage/local_store_load.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/library/library_store.dart';
import 'package:bayaz_ai/features/library/saved_test.dart';
import 'package:bayaz_ai/features/omr/grade_papers_screen.dart';
import 'package:bayaz_ai/features/omr/gradebook_store.dart';
import 'package:bayaz_ai/features/omr/graded_result.dart';
import 'package:bayaz_ai/features/omr/grading_screen.dart';
import 'package:bayaz_ai/features/omr/omr_grader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Library extends LibraryStore {
  _Library(this.items);
  final List<SavedTest> items;
  @override
  Future<LocalStoreLoad<SavedTest>> load() async =>
      LocalStoreLoad(items: items);
}

class _Gradebook extends GradebookStore {
  @override
  Future<List<GradedResult>> listForTest(String testId) async => const [];
  @override
  Future<void> save(GradedResult result) async {}
}

const context = TeachingContext(
  className: 'Class 6',
  subjectName: 'General Science',
);
McqTest paper() => McqTest(
  id: 'paper-1',
  topic: 'Cells',
  expectedCount: 5,
  questions: List.generate(
    5,
    (i) => McqQuestion(
      number: i + 1,
      difficulty: 'easy',
      text: 'Q${i + 1}',
      options: const {'A': 'a', 'B': 'b', 'C': 'c', 'D': 'd'},
      answer: 'A',
    ),
  ),
);

void main() {
  testWidgets('Home grading chooser shows saved tests without paper ids', (
    tester,
  ) async {
    final saved = SavedTest(
      id: 'paper-1',
      kind: 'mcq',
      topic: 'Cells',
      createdAtMillis: 10,
      contentJson: paper().toJson(),
      teachingContext: context,
    );
    await tester.pumpWidget(
      MaterialApp(home: GradePapersScreen(store: _Library([saved]))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Which test are you grading?'), findsOneWidget);
    expect(find.text('Cells'), findsOneWidget);
    expect(find.text('Class 6 · General Science'), findsOneWidget);
    expect(find.textContaining('paper-1'), findsNothing);
  });

  testWidgets('uncertain answers are resolved individually before save', (
    tester,
  ) async {
    final result = OmrResult(
      fiducialsFound: true,
      questions: [
        const OmrQuestion(
          number: 1,
          marked: null,
          correct: 'A',
          fill: .1,
          confidence: .02,
        ),
        const OmrQuestion(
          number: 2,
          marked: 'A',
          correct: 'A',
          fill: .8,
          confidence: .6,
        ),
        const OmrQuestion(
          number: 3,
          marked: 'B',
          correct: 'A',
          fill: .8,
          confidence: .6,
        ),
        const OmrQuestion(
          number: 4,
          marked: 'A',
          correct: 'A',
          fill: .8,
          confidence: .6,
        ),
        const OmrQuestion(
          number: 5,
          marked: 'A',
          correct: 'A',
          fill: .8,
          confidence: .6,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GradingScreen(
          test: paper(),
          teachingContext: context,
          initialResult: result,
          gradebookStore: _Gradebook(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Bayaz couldn’t clearly read this answer.'),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save result'),
    );
    expect(save.onPressed, isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Blank'));
    await tester.pump();
    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save result'),
    );
    expect(enabled.onPressed, isNotNull);
  });
}
