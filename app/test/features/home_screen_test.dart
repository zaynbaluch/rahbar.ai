import 'package:bayaz_ai/core/storage/local_store_load.dart';
import 'package:bayaz_ai/features/curriculum/recent_work_store.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/library/library_store.dart';
import 'package:bayaz_ai/features/library/saved_test.dart';
import 'package:bayaz_ai/features/omr/gradebook_store.dart';
import 'package:bayaz_ai/features/omr/graded_result.dart';
import 'dart:async';
import 'dart:io';

import 'package:bayaz_ai/features/curriculum/curriculum_home_screen.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:bayaz_ai/features/resources/background_ai_download_controller.dart';
import 'package:bayaz_ai/features/resources/download_manager.dart';
import 'package:bayaz_ai/features/resources/local_ai_resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends OnboardingStore {
  @override
  Future<OnboardingState> read() async =>
      const OnboardingState(completed: true, teacherName: 'Ayesha');
}

class _SlowResources extends LocalAiResources {
  final Completer<File> download = Completer<File>();
  @override
  Future<LocalAiAvailability> inspect() async => const LocalAiAvailability(
    languageModel: LocalAiComponentAvailability(
      resource: null,
      installed: false,
      downloadConfigured: true,
    ),
    embeddingModel: LocalAiComponentAvailability(
      resource: null,
      installed: true,
      downloadConfigured: true,
    ),
  );
  @override
  Future<File> installLanguageModel({
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) {
    onProgress?.call(const DownloadProgress(receivedBytes: 1, totalBytes: 2));
    return download.future;
  }

  @override
  void dispose() {}
}

class _Library extends LibraryStore {
  _Library(this.items);
  final List<SavedTest> items;
  @override
  Future<LocalStoreLoad<SavedTest>> load() async =>
      LocalStoreLoad(items: items);
}

class _RecentStore extends RecentWorkStore {
  _RecentStore({this.reference, this.active});
  RecentWorkReference? reference;
  String? active;

  @override
  Future<RecentWorkReference?> current() async => reference;
  @override
  Future<String?> activeGradingTestId() async => active;
  @override
  Future<void> update(RecentWorkReference value) async => reference = value;
  @override
  Future<void> setActiveGrading(String testId) async => active = testId;
  @override
  Future<void> clearActiveGrading() async => active = null;
  @override
  Future<void> clearRecent() async => reference = null;
  @override
  Future<void> invalidateTarget(String id) async {
    if (active == id) active = null;
    if (reference?.id == id) reference = null;
  }
}

class _Gradebook extends GradebookStore {
  _Gradebook(this.items);
  final List<GradedResult> items;
  @override
  Future<List<GradedResult>> listForTest(String testId) async =>
      items.where((item) => item.testId == testId).toList(growable: false);
}

McqTest _paper() => McqTest(
  id: 'test-1',
  topic: 'Cells',
  expectedCount: 5,
  questions: List.generate(
    5,
    (index) => McqQuestion(
      number: index + 1,
      difficulty: 'easy',
      text: 'Question',
      options: const {'A': 'a', 'B': 'b', 'C': 'c', 'D': 'd'},
      answer: 'A',
    ),
  ),
);

void main() {
  testWidgets('home is action-first and shows the teacher greeting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CurriculumHomeScreen(onboardingStore: _Store())),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Ayesha'), findsOneWidget);
    expect(find.text('Prepare Lesson'), findsOneWidget);
    expect(find.text('Create Test'), findsOneWidget);
    expect(find.text('Grade Papers'), findsOneWidget);
    expect(find.text('Continue Recent'), findsOneWidget);
    expect(find.text('Browse coursework'), findsNothing);
    expect(find.text('Recently accessed'), findsNothing);
    expect(find.byTooltip('Open Settings'), findsOneWidget);
  });

  testWidgets('download card can be dismissed without cancelling setup', (
    tester,
  ) async {
    final resources = _SlowResources();
    final controller = BackgroundAiDownloadController(resources: resources);
    unawaited(controller.startIfNeeded());
    await tester.pumpWidget(
      MaterialApp(
        home: CurriculumHomeScreen(
          onboardingStore: _Store(),
          backgroundAiController: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Preparing offline AI'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide download progress'));
    await tester.pump();
    expect(find.text('Preparing offline AI'), findsNothing);
    expect(controller.state.running, isTrue);
    resources.download.complete(File('/tmp/model.gguf'));
    await tester.pump();
  });

  testWidgets('Continue Recent prioritizes an active grading session', (
    tester,
  ) async {
    final recent = _RecentStore(
      reference: const RecentWorkReference(type: 'lesson', id: 'older-lesson'),
      active: 'test-1',
    );
    final saved = SavedTest(
      id: 'test-1',
      kind: 'mcq',
      topic: 'Cells',
      createdAtMillis: 1,
      contentJson: _paper().toJson(),
      teachingContext: const TeachingContext(
        className: 'Class 6',
        subjectName: 'General Science',
      ),
    );
    final graded = const GradedResult(
      id: 'g1',
      testId: 'test-1',
      testTopic: 'Cells',
      studentName: 'Student 1',
      correct: 4,
      total: 5,
      marks: 'A|A|A|A|B',
      correctAnswers: 'A|A|A|A|A',
      createdAtMillis: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CurriculumHomeScreen(
          onboardingStore: _Store(),
          recentWorkStore: recent,
          libraryStore: _Library([saved]),
          gradebookStore: _Gradebook([graded]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue grading'), findsOneWidget);
    expect(find.text('Cells · 1 papers graded'), findsOneWidget);
  });

  testWidgets('invalid recent target falls back to My Work', (tester) async {
    final recent = _RecentStore(
      reference: const RecentWorkReference(type: 'test', id: 'missing-test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CurriculumHomeScreen(
          onboardingStore: _Store(),
          recentWorkStore: recent,
          libraryStore: _Library(const []),
          gradebookStore: _Gradebook(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue Recent'), findsOneWidget);
    expect(find.text('Open My Work'), findsOneWidget);
    expect(await recent.current(), isNull);
  });

  testWidgets('home uses a tappable elevated 2 by 2 card grid on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: CurriculumHomeScreen(onboardingStore: _Store())),
    );
    await tester.pumpAndSettle();

    Rect cardRect(String label) => tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    final lesson = cardRect('Prepare Lesson');
    final test = cardRect('Create Test');
    final grade = cardRect('Grade Papers');
    final recent = cardRect('Continue Recent');
    expect((lesson.center.dy - test.center.dy).abs(), lessThan(3));
    expect((grade.center.dy - recent.center.dy).abs(), lessThan(3));
    expect(lesson.center.dx, lessThan(test.center.dx));
    expect(grade.center.dx, lessThan(recent.center.dx));
    expect(lesson.center.dy, lessThan(grade.center.dy));
    final cardMaterial = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Prepare Lesson'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(cardMaterial.elevation, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
