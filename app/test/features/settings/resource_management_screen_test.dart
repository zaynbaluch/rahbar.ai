import 'dart:async';
import 'dart:io';

import 'package:bayaz_ai/features/resources/download_manager.dart';
import 'package:bayaz_ai/features/resources/resource_manager.dart';
import 'package:bayaz_ai/features/resources/resource_manifest.dart';
import 'package:bayaz_ai/features/settings/resource_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubResourceManager extends ResourceManager {
  _StubResourceManager(this._resources, {Set<String>? installed})
    : installed = installed ?? <String>{};

  final List<ResourceDescriptor> _resources;
  final Set<String> installed;
  final downloads = <String, Completer<File>>{};
  void Function(DownloadProgress progress)? onProgress;
  DownloadCancellationToken? token;

  @override
  Future<void> init() async {}
  @override
  List<ResourceDescriptor> resources({ResourceKind? kind}) =>
      _resources.where((r) => kind == null || r.kind == kind).toList();
  @override
  Future<bool> isInstalled(String id) async =>
      _resources.firstWhere((r) => r.id == id).isBundled ||
      installed.contains(id);
  @override
  Future<File> install(
    String id, {
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) {
    token = cancellationToken;
    this.onProgress = onProgress;
    final c = Completer<File>();
    downloads[id] = c;
    return c.future.then((file) {
      installed.add(id);
      return file;
    });
  }

  @override
  Future<void> remove(String id) async => installed.remove(id);
  @override
  void dispose() {}
}

const _curriculum = ResourceDescriptor(
  id: 'curriculum.test',
  kind: ResourceKind.curriculumModule,
  version: '1',
  displayName: 'Class 6 General Science',
  fileName: 'content.db',
  sizeBytes: 0,
  sha256: '',
  required: true,
  licenseName: '',
  licenseUrl: '',
  bundledAsset: 'assets/content/content_pack.db',
);
final _language = ResourceDescriptor(
  id: 'language.private.internal',
  kind: ResourceKind.languageModel,
  version: '1',
  displayName: 'Secret model name',
  fileName: 'model.gguf',
  sizeBytes: 100 * 1024 * 1024,
  sha256: 'a' * 64,
  required: false,
  licenseName: 'provider license',
  licenseUrl: '',
  downloadUrl: Uri.parse('https://example.test/language'),
);
final _embedding = ResourceDescriptor(
  id: 'embedding.private.internal',
  kind: ResourceKind.embeddingModel,
  version: '1',
  displayName: 'Secret embedding name',
  fileName: 'embed.gguf',
  sizeBytes: 50 * 1024 * 1024,
  sha256: 'b' * 64,
  required: false,
  licenseName: 'provider license',
  licenseUrl: '',
  downloadUrl: Uri.parse('https://example.test/embedding'),
);

Future<void> _pump(WidgetTester tester, _StubResourceManager manager) async {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: ResourceManagementScreen(manager: manager)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offline AI page is aggregate and hides model internals', (
    tester,
  ) async {
    final manager = _StubResourceManager([_curriculum, _language, _embedding]);
    await _pump(tester, manager);
    expect(find.text('Offline AI'), findsOneWidget);
    expect(find.text('Needs download'), findsOneWidget);
    expect(find.text('Download Offline AI'), findsOneWidget);
    expect(find.textContaining('Secret model'), findsNothing);
    expect(find.textContaining('embedding'), findsNothing);
    expect(find.textContaining('SHA'), findsNothing);
    expect(find.textContaining('provider'), findsNothing);
    expect(find.textContaining('coursework'), findsNothing);
  });

  testWidgets('download begins with generic progress and can be cancelled', (
    tester,
  ) async {
    final manager = _StubResourceManager([_language]);
    await _pump(tester, manager);
    await tester.tap(find.text('Download Offline AI'));
    await tester.pump();
    expect(find.text('Starting download…'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(manager.token, isNotNull);
    manager.onProgress!(
      const DownloadProgress(receivedBytes: 50, totalBytes: 100),
    );
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);
    manager.token!.cancel();
    manager.downloads.values.single.completeError(const DownloadCancelled());
    await tester.pumpAndSettle();
  });

  testWidgets('ready state offers removal without exposing file details', (
    tester,
  ) async {
    final manager = _StubResourceManager(
      [_language, _embedding],
      installed: {_language.id, _embedding.id},
    );
    await _pump(tester, manager);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Remove downloads'), findsOneWidget);
    expect(find.textContaining('.gguf'), findsNothing);
  });
}
