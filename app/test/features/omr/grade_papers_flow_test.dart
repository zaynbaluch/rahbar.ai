import 'package:bayaz_ai/core/storage/local_store_load.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/library/library_store.dart';
import 'package:bayaz_ai/features/library/saved_test.dart';
import 'package:bayaz_ai/features/omr/grade_papers_screen.dart';
import 'package:bayaz_ai/features/omr/gradebook_store.dart';
import 'package:bayaz_ai/features/omr/graded_result.dart';
import 'package:bayaz_ai/features/omr/grading_screen.dart';
import 'package:bayaz_ai/features/omr/omr_diagnostics.dart';
import 'package:bayaz_ai/features/omr/omr_grader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('scan diagnostics are expandable and copyable after a read', (
    tester,
  ) async {
    const diagnostics = OmrDiagnostics(
      status: OmrScanStatus.complete,
      failureCode: OmrFailureCode.none,
      sourceWidth: 1080,
      sourceHeight: 1440,
      canonicalWidth: 820,
      canonicalHeight: 1160,
      markerCandidateCount: 6,
      registrationScore: .91,
      registrationNote: 'registered four consistent corner markers',
      stageTimingsMs: {
        'quality': 4,
        'registration': 16,
        'rectification': 30,
        'analysis': 8,
        'total': 58,
      },
      markThreshold: .14,
    );
    const result = OmrResult(
      fiducialsFound: true,
      diagnostics: diagnostics,
      questions: [
        OmrQuestion(
          number: 1,
          marked: 'A',
          correct: 'A',
          fill: .8,
          confidence: .9,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GradingScreen(
          test: paper(),
          initialResult: result,
          gradebookStore: _Gradebook(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan diagnostics'), findsOneWidget);
    expect(find.textContaining('status=complete'), findsNothing);
    await tester.tap(find.text('Scan diagnostics'));
    await tester.pumpAndSettle();
    expect(find.textContaining('status=complete'), findsOneWidget);
    expect(find.text('Copy diagnostics'), findsOneWidget);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final copyButton = find.widgetWithText(OutlinedButton, 'Copy diagnostics');
    await tester.ensureVisible(copyButton);
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(find.text('Scan diagnostics copied'), findsOneWidget);
  });

  testWidgets('registration failure keeps its diagnostic evidence visible', (
    tester,
  ) async {
    const diagnostics = OmrDiagnostics(
      status: OmrScanStatus.rejected,
      failureCode: OmrFailureCode.fiducialsNotFound,
      sourceWidth: 1080,
      sourceHeight: 1440,
      markerCandidateCount: 2,
      registrationNote: 'only 2 square-like marker candidates were found',
      stageTimingsMs: {'quality': 4, 'registration': 12, 'total': 16},
    );
    const rejected = OmrResult(
      fiducialsFound: false,
      diagnostics: diagnostics,
      questions: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GradingScreen(
          test: paper(),
          initialResult: rejected,
          gradebookStore: _Gradebook(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t read this answer sheet'), findsOneWidget);
    expect(find.text('Scan diagnostics'), findsOneWidget);
    expect(find.textContaining('failure=fiducialsNotFound'), findsOneWidget);
    expect(
      find.textContaining('only 2 square-like marker candidates'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets(
    'rejected scan with detected markers stays in the read-error state',
    (tester) async {
      final rejected = OmrResult(
        fiducialsFound: true,
        diagnostics: const OmrDiagnostics(
          status: OmrScanStatus.rejected,
          failureCode: OmrFailureCode.templateMismatch,
          sourceWidth: 1080,
          sourceHeight: 1440,
          canonicalWidth: 820,
          canonicalHeight: 1160,
          markerCandidateCount: 14,
          registrationNote: 'markers found but sheet template did not validate',
        ),
        questions: [
          for (var i = 1; i <= 5; i++)
            OmrQuestion(
              number: i,
              marked: null,
              correct: 'A',
              fill: 0,
              confidence: 0,
            ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GradingScreen(
            test: paper(),
            teachingContext: context,
            initialResult: rejected,
            gradebookStore: _Gradebook(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t read this answer sheet'), findsOneWidget);
      expect(
        find.text(
          'This image doesn’t match the Bayaz answer grid. Use the answer box from a test PDF created by Bayaz.',
        ),
        findsOneWidget,
      );
      expect(find.text('0 / 5'), findsNothing);
      expect(find.text('Scan diagnostics'), findsOneWidget);
    },
  );
}
