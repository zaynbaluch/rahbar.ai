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
}
