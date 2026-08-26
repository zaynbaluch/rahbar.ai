import 'package:bayaz_ai/core/storage/local_store_load.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/library/library_store.dart';
import 'package:bayaz_ai/features/library/saved_test.dart';
import 'package:bayaz_ai/features/omr/gradebook_store.dart';
import 'package:bayaz_ai/features/omr/graded_result.dart';
import 'package:bayaz_ai/features/omr/results_overview_screen.dart';
import 'package:bayaz_ai/features/omr/results_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const ctx = TeachingContext(
  className: 'Class 6',
  subjectName: 'General Science',
);
final results = [
  const GradedResult(
    id: '1',
    testId: 't1',
    testTopic: 'Cells',
    studentName: 'Ayesha',
    correct: 2,
    total: 3,
    marks: 'A|B|C',
    correctAnswers: 'A|A|C',
    createdAtMillis: 100,
    teachingContext: ctx,
  ),
  const GradedResult(
    id: '2',
    testId: 't1',
    testTopic: 'Cells',
    studentName: 'Bilal',
    correct: 1,
    total: 3,
    marks: 'B||C',
    correctAnswers: 'A|A|C',
    createdAtMillis: 90,
    teachingContext: ctx,
  ),
];

class _Gradebook extends GradebookStore {
  _Gradebook(this.items);
  final List<GradedResult> items;
  @override
  Future<LocalStoreLoad<GradedResult>> loadAll() async =>
      LocalStoreLoad(items: items);
  @override
  Future<LocalStoreLoad<GradedResult>> loadForTest(String id) async =>
      LocalStoreLoad(items: items.where((e) => e.testId == id).toList());
  @override
  Future<void> delete(String id) async {}
}

class _Library extends LibraryStore {
  _Library(this.items);
  final List<SavedTest> items;
  @override
  Future<LocalStoreLoad<SavedTest>> load() async =>
      LocalStoreLoad(items: items);
}

McqTest testPaper() => McqTest(
  id: 't1',
  topic: 'Cells',
  expectedCount: 3,
  questions: List.generate(
    3,
    (i) => McqQuestion(
      number: i + 1,
      difficulty: 'easy',
      text: 'Stem ${i + 1}',
      options: const {'A': 'a', 'B': 'b', 'C': 'c', 'D': 'd'},
      answer: i == 2 ? 'C' : 'A',
    ),
  ),
);

void main() {
  test('question performance ranks most missed and counts blanks', () {
    final perf = calculateQuestionPerformance(results);
    expect(perf.first.questionNumber, 2);
    expect(perf.first.wrong, 2);
    expect(perf.first.blank, 1);
    expect(perf.first.distribution['B'], 1);
  });

  testWidgets('overview is teacher-facing and omits test ids', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ResultsOverviewScreen(store: _Gradebook(results))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Class Results'), findsOneWidget);
    expect(find.text('Class 6 · General Science'), findsOneWidget);
    expect(find.textContaining('t1'), findsNothing);
    expect(find.textContaining('2 students'), findsOneWidget);
  });

  testWidgets('detail remains readable when original test is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(
          testId: 't1',
          topic: 'Cells',
          store: _Gradebook(results),
          libraryStore: _Library(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Grade more papers'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.text('Ayesha'), findsOneWidget);
  });

  testWidgets('detail can grade more when exact saved test exists', (
    tester,
  ) async {
    final saved = SavedTest(
      id: 't1',
      kind: 'mcq',
      topic: 'Cells',
      createdAtMillis: 1,
      contentJson: testPaper().toJson(),
      teachingContext: ctx,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(
          testId: 't1',
          topic: 'Cells',
          store: _Gradebook(results),
          libraryStore: _Library([saved]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 3 && find.text('Grade more papers').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
    }
    expect(find.text('Grade more papers'), findsOneWidget);
  });
}
