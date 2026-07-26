import 'dart:async';
import 'dart:io';

import 'package:bayaz_ai/features/resources/download_manager.dart';
import 'package:bayaz_ai/features/resources/resource_manager.dart';
import 'package:bayaz_ai/features/resources/resource_manifest.dart';
import 'package:bayaz_ai/features/settings/resource_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A manager that never touches the network or the file system.
///
/// [install] hands the progress callback back to the test and stays pending, so
/// the screen can be held in the state it reaches before the first progress
/// event arrives.
class _StubResourceManager extends ResourceManager {
  _StubResourceManager(this._resources);

  final List<ResourceDescriptor> _resources;
  final download = Completer<File>();
  void Function(DownloadProgress progress)? onProgress;
  DownloadCancellationToken? token;

  @override
  Future<void> init() async {}

  @override
  List<ResourceDescriptor> resources({ResourceKind? kind}) => _resources
      .where((resource) => kind == null || resource.kind == kind)
      .toList(growable: false);

  @override
  Future<bool> isInstalled(String id) async =>
      _resources.firstWhere((resource) => resource.id == id).isBundled;

  @override
  Future<File> install(
    String id, {
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) {
    token = cancellationToken;
    this.onProgress = onProgress;
    return download.future;
  }

  @override
  void dispose() {}
}

const _bundledCurriculum = ResourceDescriptor(
  id: 'curriculum.test.class6',
  kind: ResourceKind.curriculumModule,
  version: '1.0.0',
  displayName: 'Class 6 General Science',
  fileName: 'content_pack.db',
  sizeBytes: 0,
  sha256: '',
  required: true,
  licenseName: '',
  licenseUrl: '',
  bundledAsset: 'assets/content/content_pack.db',
);

final _languageModel = ResourceDescriptor(
  id: 'model.test.language',
  kind: ResourceKind.languageModel,
  version: '1.0.0',
  displayName: 'Test language model',
  fileName: 'model.gguf',
  sizeBytes: 104857600,
  sha256: 'a' * 64,
  required: false,
  licenseName: '',
  licenseUrl: '',
  downloadUrl: Uri.parse('https://example.test/model.gguf'),
);

/// A viewport tall enough to lay out every card, so the list does not defer
/// building the model section the tests look at.
Future<void> _pumpScreen(
  WidgetTester tester,
  _StubResourceManager manager,
) async {
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: ResourceManagementScreen(manager: manager)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a download that has not reported progress yet does not crash', (
    tester,
  ) async {
    final manager = _StubResourceManager([_bundledCurriculum, _languageModel]);
    await _pumpScreen(tester, manager);

    await tester.tap(find.text('Download'));
    // A single frame: the card is downloading, but `install` has not called back
    // yet, so the progress value is still null. An indeterminate bar animates
    // forever, so this must not be a `pumpAndSettle`.
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(manager.token, isNotNull);
    expect(find.text('Starting download…'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);

    manager.onProgress!(
      const DownloadProgress(receivedBytes: 52428800, totalBytes: 104857600),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Starting download…'), findsNothing);
    expect(find.text('50 MB of 100 MB'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );

    // Leave the screen idle so no animation or pending download outlives the
    // test.
    manager.download.completeError(const DownloadCancelled());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('bundled coursework reads as included, not misconfigured', (
    tester,
  ) async {
    final manager = _StubResourceManager([_bundledCurriculum, _languageModel]);
    await _pumpScreen(tester, manager);

    expect(find.text('Coursework module - Included with app'), findsOneWidget);
    expect(find.textContaining('Size not configured'), findsNothing);
    expect(find.text('Content generation model - 100 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
