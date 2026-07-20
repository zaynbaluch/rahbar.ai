import 'dart:io';

import 'download_manager.dart';
import 'resource_manifest.dart';

class ResourceManager {
  ResourceManager({ResourceDownloadManager? downloads})
      : _downloads = downloads ?? ResourceDownloadManager();

  final ResourceDownloadManager _downloads;
  ResourceManifest? _manifest;

  ResourceManifest get manifest {
    final value = _manifest;
    if (value == null) {
      throw StateError('ResourceManager.init must be called first.');
    }
    return value;
  }

  Future<void> init() async {
    _manifest ??= await ResourceManifest.loadBundled();
  }

  List<ResourceDescriptor> resources({ResourceKind? kind}) => manifest.resources
      .where((resource) => kind == null || resource.kind == kind)
      .toList(growable: false);

  Future<bool> isInstalled(String id) async {
    final resource = _find(id);
    return resource.isBundled || _downloads.verifyIntegrity(resource);
  }

  Future<File?> installedFile(String id) async {
    final resource = _find(id);
    if (resource.isBundled || !await _downloads.verifyIntegrity(resource)) {
      return null;
    }
    return _downloads.installedFile(resource);
  }

  Future<File> install(
    String id, {
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) {
    final resource = _find(id);
    if (resource.isBundled) {
      throw StateError('${resource.displayName} is already included in the app.');
    }
    return _downloads.download(
      resource,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );
  }

  Future<bool> verify(String id) => _downloads.verifyIntegrity(_find(id));

  Future<void> remove(String id) => _downloads.remove(_find(id));

  ResourceDescriptor _find(String id) => manifest.resources.firstWhere(
        (resource) => resource.id == id,
        orElse: () => throw StateError('Unknown resource: $id'),
      );

  void dispose() => _downloads.dispose();
}
