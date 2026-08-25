import 'package:bayaz_ai/core/storage/local_store_load.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/library/library_screen.dart';
import 'package:bayaz_ai/features/library/library_store.dart';
import 'package:bayaz_ai/features/library/saved_test.dart';
import 'package:bayaz_ai/features/omr/gradebook_store.dart';
import 'package:bayaz_ai/features/omr/graded_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Library extends LibraryStore {
  _Library(this.items);
  final List<SavedTest> items;
  @override
  Future<LocalStoreLoad<SavedTest>> load() async =>
      LocalStoreLoad(items: items);
  @override
  Future<void> delete(String id) async {}
}

class _Gradebook extends GradebookStore {
  _Gradebook(this.items);
  final List<GradedResult> items;
  @override
  Future<List<GradedResult>> listForTest(String testId) async =>
      items.where((r) => r.testId == testId).toList();
}

final testPaper = McqTest(
  id: 't1',
  topic: 'Cells',
  expectedCount: 5,
  questions: List.generate(
    5,
    (i) => McqQuestion(
      number: i + 1,
      difficulty: 'easy',
      text: 'Q',
      options: const {'A': 'a', 'B': 'b', 'C': 'c', 'D': 'd'},
      answer: 'A',
    ),
  ),
);
const context = TeachingContext(
  className: 'Class 6',
  subjectName: 'General Science',
);

void main() {
  testWidgets('My Work cards show teacher metadata without provenance badges', (
    tester,
  ) async {
    final item = SavedTest(
      id: 't1',
      kind: 'mcq',
      source: SavedContentSource.customAi,
      topic: 'Cells',
      createdAtMillis: 10,
      contentJson: testPaper.toJson(),
      teachingContext: context,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          store: _Library([item]),
          gradebookStore: _Gradebook(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Work'), findsOneWidget);
    expect(find.text('Test · 5 questions'), findsOneWidget);
    expect(find.text('Class 6 · General Science'), findsOneWidget);
    expect(find.textContaining('Custom AI'), findsNothing);
    expect(find.textContaining('Curriculum pack'), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
  });

  testWidgets('search matches class and subject', (tester) async {
    final item = SavedTest(
      id: 't1',
      kind: 'mcq',
      topic: 'Cells',
      createdAtMillis: 10,
      contentJson: testPaper.toJson(),
      teachingContext: context,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          store: _Library([item]),
          gradebookStore: _Gradebook(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'science');
    await tester.pump();
    expect(find.text('Cells'), findsOneWidget);
  });
}
