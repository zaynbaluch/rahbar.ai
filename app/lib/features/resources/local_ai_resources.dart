import 'dart:io';

import 'download_manager.dart';
import 'resource_manager.dart';
import 'resource_manifest.dart';

class LocalAiComponentAvailability {
  const LocalAiComponentAvailability({
    required this.resource,
    required this.installed,
    required this.downloadConfigured,
    this.file,
  });

  final ResourceDescriptor? resource;
  final bool installed;
  final bool downloadConfigured;
  final File? file;
}

class LocalAiAvailability {
  const LocalAiAvailability({
    required this.languageModel,
    required this.embeddingModel,
  });

  final LocalAiComponentAvailability languageModel;
  final LocalAiComponentAvailability embeddingModel;

  bool get canGenerate => languageModel.installed;
  bool get canGenerateGrounded =>
      languageModel.installed && embeddingModel.installed;
  bool get fullyConfigured => canGenerateGrounded;
}

class LocalAiResources {
  LocalAiResources({ResourceManager? manager})
      : _manager = manager ?? ResourceManager();

  final ResourceManager _manager;

  Future<LocalAiAvailability> inspect() async {
    await _manager.init();
    return LocalAiAvailability(
      languageModel: await _inspectKind(ResourceKind.languageModel),
      embeddingModel: await _inspectKind(ResourceKind.embeddingModel),
    );
  }

  Future<LocalAiComponentAvailability> _inspectKind(ResourceKind kind) async {
    final candidates = _manager.resources(kind: kind);
    if (candidates.isEmpty) {
      return const LocalAiComponentAvailability(
        resource: null,
        installed: false,
        downloadConfigured: false,
      );
    }
    final resource = candidates.first;
    final installed = await _manager.isInstalled(resource.id);
    return LocalAiComponentAvailability(
      resource: resource,
      installed: installed,
      downloadConfigured: resource.isDownloadable,
      file: installed ? await _manager.installedFile(resource.id) : null,
    );
  }

  Future<File> installLanguageModel({
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) => _installFirst(
        ResourceKind.languageModel,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
      );

  Future<File> installEmbeddingModel({
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) => _installFirst(
        ResourceKind.embeddingModel,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
      );

  Future<File> _installFirst(
    ResourceKind kind, {
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    await _manager.init();
    final candidates = _manager.resources(kind: kind);
    if (candidates.isEmpty) {
      throw StateError('No ${resourceKindWireName(kind)} is listed in the resource manifest.');
    }
    return _manager.install(
      candidates.first.id,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );
  }

  void dispose() => _manager.dispose();
}
