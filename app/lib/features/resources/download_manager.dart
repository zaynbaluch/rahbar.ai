import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'resource_manifest.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

class DownloadIntegrityException implements Exception {
  const DownloadIntegrityException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DownloadCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double? get fraction => totalBytes <= 0
      ? null
      : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

class ResourceDownloadManager {
  ResourceDownloadManager({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<Directory> resourceDirectory(ResourceDescriptor resource) async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(
      support.path,
      'resources',
      resource.id,
      resource.version,
    ));
  }

  Future<File> installedFile(ResourceDescriptor resource) async {
    final directory = await resourceDirectory(resource);
    return File(p.join(directory.path, resource.fileName));
  }

  Future<bool> verifyIntegrity(ResourceDescriptor resource) async {
    if (resource.isBundled) return true;
    final file = await installedFile(resource);
    if (!await file.exists()) return false;
    if (resource.sizeBytes > 0 && await file.length() != resource.sizeBytes) {
      return false;
    }
    return _matchesHash(file, resource.sha256);
  }

  Future<File> download(
    ResourceDescriptor resource, {
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final url = resource.downloadUrl;
    if (url == null) {
      throw StateError('No provider download URL is configured for ${resource.displayName}.');
    }
    if (await verifyIntegrity(resource)) return installedFile(resource);

    final directory = await resourceDirectory(resource);
    await directory.create(recursive: true);
    final destination = await installedFile(resource);
    final partial = File('${destination.path}.download');
    if (await partial.exists()) await partial.delete();

    final request = await _client.getUrl(url).timeout(const Duration(seconds: 30));
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Download failed with HTTP ${response.statusCode}.',
        uri: url,
      );
    }
    for (final redirect in response.redirects) {
      if (redirect.location.scheme != 'https') {
        await response.drain<void>();
        throw const DownloadIntegrityException(
          'The download redirected to an insecure address.',
        );
      }
    }

    final sink = partial.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 90))) {
        if (cancellationToken?.isCancelled ?? false) {
          throw const DownloadCancelled();
        }
        received += chunk.length;
        if (received > resource.sizeBytes) {
          throw const DownloadIntegrityException(
            'The download exceeded the expected file size.',
          );
        }
        sink.add(chunk);
        onProgress?.call(DownloadProgress(
          receivedBytes: received,
          totalBytes: resource.sizeBytes,
        ));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (received != resource.sizeBytes) {
      if (await partial.exists()) await partial.delete();
      throw DownloadIntegrityException(
        'Downloaded $received bytes; expected ${resource.sizeBytes}.',
      );
    }
    if (!await _matchesHash(partial, resource.sha256)) {
      await partial.delete();
      throw const DownloadIntegrityException(
        'The SHA-256 checksum did not match. Please retry the download.',
      );
    }
    if (await destination.exists()) await destination.delete();
    return partial.rename(destination.path);
  }

  Future<bool> _matchesHash(File file, String expected) async {
    if (expected.isEmpty) return false;
    final actual = await sha256.bind(file.openRead()).first;
    return actual.toString().toLowerCase() == expected.toLowerCase();
  }

  Future<void> remove(ResourceDescriptor resource) async {
    if (resource.isBundled) {
      throw StateError('Bundled resources cannot be removed.');
    }
    final directory = await resourceDirectory(resource);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  void dispose() => _client.close(force: true);
}
