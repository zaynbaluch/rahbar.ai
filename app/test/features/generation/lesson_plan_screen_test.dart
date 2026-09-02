import 'dart:typed_data';

import 'package:bayaz_ai/core/storage/local_store_load.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/lesson_plan.dart';
import 'package:bayaz_ai/features/generation/lesson_plan_view.dart';
import 'package:bayaz_ai/features/library/library_store.dart';
import 'package:bayaz_ai/features/library/library_screen.dart';
import 'package:bayaz_ai/features/library/saved_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Library extends LibraryStore {
  final saved = <SavedTest>[];
  @override
  Future<void> save(SavedTest test) async => saved.add(test);
  @override
  Future<LocalStoreLoad<SavedTest>> load() async =>
      LocalStoreLoad(items: saved);
}

const _plan = LessonPlan(
  topicId: 'plants',
  topic: 'Plants',
  slos: ['Explain photosynthesis.'],
  sections: [
    PlanSection(
      id: 'engage-1',
      section: 'engage',
      variantLabel: 'leaf',
      minutes: 7,
      body: 'Look at a leaf.',
      materials: ['leaf'],
    ),
  ],
);

const _context = TeachingContext(
  classCode: '8',
  className: 'Class 8',
  subjectCode: 'biology',
  subjectName: 'Biology',
);

void main() {
  testWidgets(
    'new lesson viewer shows teaching context and save/share actions',
    (tester) async {
      final library = _Library();
      var shared = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LessonPlanScreen(
            plan: _plan,
            teachingContext: _context,
            libraryStore: library,
            sharePdf:
                ({required Uint8List bytes, required String filename}) async {
                  shared = bytes.isNotEmpty && filename.endsWith('.pdf');
                  return true;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Class 8 · Biology'), findsOneWidget);
      expect(find.text('7 minutes total'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Save in Bayaz'), findsOneWidget);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(library.saved, hasLength(1));
      expect(library.saved.single.teachingContext?.className, 'Class 8');
      expect(shared, isTrue);
      expect(find.text('✓ Saved in Bayaz & shared'), findsOneWidget);
    },
  );

  testWidgets('saved lesson reopens with its teaching context', (tester) async {
    final saved = SavedTest(
      id: 'saved-plan',
      kind: 'lesson',
      topic: 'Plants',
      createdAtMillis: 1,
      contentJson: _plan.toJson(),
      teachingContext: _context,
    );
    await tester.pumpWidget(MaterialApp(home: SavedTestScreen(test: saved)));
    await tester.pump();

    expect(find.text('Class 8 · Biology'), findsOneWidget);
    expect(find.text('Save in Bayaz'), findsNothing);
  });

  testWidgets('reopened lesson is share-only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LessonPlanReadOnlyScreen(plan: _plan, teachingContext: _context),
      ),
    );
    await tester.pump();

    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save in Bayaz'), findsNothing);
  });
}
