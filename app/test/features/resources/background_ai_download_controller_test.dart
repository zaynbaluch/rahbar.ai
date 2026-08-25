import 'dart:io';

import 'package:bayaz_ai/features/resources/background_ai_download_controller.dart';
import 'package:bayaz_ai/features/resources/download_manager.dart';
import 'package:bayaz_ai/features/resources/local_ai_resources.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeResources extends LocalAiResources {
  _FakeResources({required this.languageInstalled, required this.embeddingInstalled});
  bool languageInstalled;
  bool embeddingInstalled;
  int languageInstalls = 0;
  int embeddingInstalls = 0;

  @override
  Future<LocalAiAvailability> inspect() async => LocalAiAvailability(
    languageModel: LocalAiComponentAvailability(resource: null, installed: languageInstalled, downloadConfigured: true),
    embeddingModel: LocalAiComponentAvailability(resource: null, installed: embeddingInstalled, downloadConfigured: true),
  );

  @override
  Future<File> installLanguageModel({DownloadCancellationToken? cancellationToken, void Function(DownloadProgress progress)? onProgress}) async {
    languageInstalls++;
    onProgress?.call(const DownloadProgress(receivedBytes: 1, totalBytes: 2));
    languageInstalled = true;
    return File('/tmp/language.gguf');
  }

  @override
  Future<File> installEmbeddingModel({DownloadCancellationToken? cancellationToken, void Function(DownloadProgress progress)? onProgress}) async {
    embeddingInstalls++;
    onProgress?.call(const DownloadProgress(receivedBytes: 1, totalBytes: 2));
    embeddingInstalled = true;
    return File('/tmp/embed.gguf');
  }

  @override
  void dispose() {}
}

void main() {
  test('preinstalled resources complete without downloading', () async {
    final resources = _FakeResources(languageInstalled: true, embeddingInstalled: true);
    final controller = BackgroundAiDownloadController(resources: resources);
    await controller.startIfNeeded();
    expect(controller.state.completed, isTrue);
    expect(resources.languageInstalls + resources.embeddingInstalls, 0);
  });

  test('automatic setup downloads only missing resources', () async {
    final resources = _FakeResources(languageInstalled: false, embeddingInstalled: true);
    final controller = BackgroundAiDownloadController(resources: resources);
    await controller.startIfNeeded();
    expect(controller.state.completed, isTrue);
    expect(resources.languageInstalls, 1);
    expect(resources.embeddingInstalls, 0);
  });

  test('developer override suppresses automatic downloads', () async {
    final resources = _FakeResources(languageInstalled: false, embeddingInstalled: false);
    final controller = BackgroundAiDownloadController(resources: resources, autoDownloadEnabled: false);
    await controller.startIfNeeded();
    expect(controller.state.running, isFalse);
    expect(controller.state.completed, isFalse);
    expect(resources.languageInstalls + resources.embeddingInstalls, 0);
  });
}
