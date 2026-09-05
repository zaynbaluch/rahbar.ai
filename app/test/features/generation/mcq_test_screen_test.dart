import 'dart:typed_data';

import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/chat/clarification_screen.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/generation/mcq_test_view.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:bayaz_ai/features/resources/offline_ai_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

McqTest _paper([int count = 5]) => McqTest(
  id: 'GS6-SECRET',
  topic: 'Cells',
  expectedCount: count,
  questions: [
    for (var i = 1; i <= count; i++)
      McqQuestion(
        number: i,
        difficulty: 'hard',
        text: 'Question $i?',
        options: const {'A': 'Correct', 'B': 'Two', 'C': 'Three', 'D': 'Four'},
        answer: 'A',
      ),
  ],
);

const _context = TeachingContext(
  classCode: '6',
  className: 'Class 6',
  subjectCode: 'general_science',
  subjectName: 'Science',
);

void main() {
  testWidgets(
    'test viewer hides technical metadata and exposes teacher actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: McqTestScreen(
            test: _paper(),
            teachingContext: _context,
            saved: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Class 6 · Science'), findsOneWidget);
      expect(find.text('5 questions'), findsOneWidget);
      expect(find.text('Paper ready'), findsNothing);
      expect(find.textContaining('GS6-SECRET'), findsNothing);
      expect(find.text('hard'), findsNothing);
      expect(find.text('Ask Bayaz'), findsNothing);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Grade sheets'), findsOneWidget);
      expect(find.text('Show answers'), findsOneWidget);

      await tester.tap(find.text('Show answers'));
      await tester.pump();
      expect(find.text('Hide answers'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
    },
  );

  testWidgets('Share saves first and then uses native PDF sharing', (
    tester,
  ) async {
    var saves = 0;
    var shares = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: McqTestScreen(
          test: _paper(),
          teachingContext: _context,
          onSave: () async => saves++,
          sharePdf:
              ({required Uint8List bytes, required String filename}) async {
                if (bytes.isNotEmpty && filename.endsWith('.pdf')) shares++;
                return true;
              },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(saves, 1);
    expect(shares, 1);
    expect(find.text('✓ Saved in Bayaz & shared'), findsOneWidget);
  });

  testWidgets('Grade sheets saves a new test before opening grading', (
    tester,
  ) async {
    var saves = 0;
    var gradingOpens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: McqTestScreen(
          test: _paper(),
          teachingContext: _context,
          onSave: () async => saves++,
          openGrading: (context, test, teachingContext) async => gradingOpens++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Grade sheets'));
    await tester.pumpAndSettle();

    expect(saves, 1);
    expect(gradingOpens, 1);
  });

  testWidgets('Ask Bayaz from a test carries its teaching context', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: McqTestScreen(
          test: _paper(),
          teachingContext: _context,
          offlineAiPolicy: OfflineAiPolicy(
            readState: () async => const OnboardingState(offlineAiEnabled: true),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Ask Bayaz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final chat = tester.widget<ClarificationScreen>(
      find.byType(ClarificationScreen),
    );
    expect(chat.teachingContext?.classCode, '6');
    expect(chat.teachingContext?.subjectCode, 'general_science');
  });

}
