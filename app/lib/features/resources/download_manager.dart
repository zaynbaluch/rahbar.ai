import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'resource_manifest.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => 'Download cancelled.';
}

class DownloadIntegrityException implements Exception {
  const DownloadIntegrityException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DownloadCancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double? get fraction =>
      totalBytes <= 0 ? null : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

class ResourceDownloadManager {
  ResourceDownloadManager({
    HttpClient? client,
    this.connectTimeout = const Duration(seconds: 30),
    this.responseTimeout = const Duration(seconds: 45),
    this.idleBodyTimeout = const Duration(seconds: 90),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration connectTimeout;
  final Duration responseTimeout;
  final Duration idleBodyTimeout;

  Future<Directory> resourceDirectory(ResourceDescriptor resource) async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      p.join(support.path, 'resources', resource.id, resource.version),
    );
  }

  Future<File> installedFile(ResourceDescriptor resource) async {
    final directory = await resourceDirectory(resource);
    return File(p.join(directory.path, resource.fileName));
  }

  Future<File> _autoDownloadSuppressionFile() async {
    final support = await getApplicationSupportDirectory();
    return File(
      p.join(
        support.path,
        'preferences',
        'offline_ai_auto_download_suppressed.v1',
      ),
    );
  }

  Future<bool> isAutoDownloadSuppressed() async =>
      (await _autoDownloadSuppressionFile()).exists();

  Future<void> setAutoDownloadSuppressed(bool suppressed) async {
    final file = await _autoDownloadSuppressionFile();
    if (suppressed) {
      await file.parent.create(recursive: true);
      if (!await file.exists()) await file.writeAsString('1', flush: true);
      return;
    }
    if (await file.exists()) await file.delete();
  }

  Future<bool> verifyIntegrity(ResourceDescriptor resource) async {
    if (resource.isBundled) return true;
    final file = await installedFile(resource);
    if (!await file.exists()) {
      await _removeIntegrityReceipt(resource);
      return false;
    }
    final size = await file.length();
    if (resource.sizeBytes > 0 && size != resource.sizeBytes) {
      await _removeIntegrityReceipt(resource);
      return false;
    }
    if (await _hasMatchingIntegrityReceipt(resource, size)) return true;

    final matches = await _matchesHash(file, resource.sha256);
    if (matches) {
      await _writeIntegrityReceipt(resource, size);
    } else {
      await _removeIntegrityReceipt(resource);
    }
    return matches;
  }

  Future<File> _integrityReceipt(ResourceDescriptor resource) async {
    final directory = await resourceDirectory(resource);
    return File(p.join(directory.path, '.integrity.receipt.json'));
  }

  Future<bool> _hasMatchingIntegrityReceipt(
    ResourceDescriptor resource,
    int size,
  ) async {
    final receipt = await _integrityReceipt(resource);
    if (!await receipt.exists()) return false;
    try {
      final json = jsonDecode(await receipt.readAsString()) as Map;
      return json['file_name'] == resource.fileName &&
          json['size_bytes'] == size &&
          (json['sha256'] as String?)?.toLowerCase() ==
              resource.sha256.toLowerCase();
    } catch (_) {
      await _removeIntegrityReceipt(resource);
      return false;
    }
  }

  Future<void> _writeIntegrityReceipt(
    ResourceDescriptor resource,
    int size,
  ) async {
    final receipt = await _integrityReceipt(resource);
    await receipt.parent.create(recursive: true);
    final temp = File('${receipt.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'file_name': resource.fileName,
        'size_bytes': size,
        'sha256': resource.sha256.toLowerCase(),
      }),
      flush: true,
    );
    if (await receipt.exists()) await receipt.delete();
    await temp.rename(receipt.path);
  }

  Future<void> _removeIntegrityReceipt(ResourceDescriptor resource) async {
    final receipt = await _integrityReceipt(resource);
    if (await receipt.exists()) await receipt.delete();
    final temp = File('${receipt.path}.tmp');
    if (await temp.exists()) await temp.delete();
  }

  Future<File> download(
    ResourceDescriptor resource, {
    DownloadCancellationToken? cancellationToken,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final url = resource.downloadUrl;
    if (url == null) {
      throw StateError(
        'No provider download URL is configured for ${resource.displayName}.',
      );
    }
    _throwIfCancelled(cancellationToken);
    if (await verifyIntegrity(resource)) return installedFile(resource);

    final directory = await resourceDirectory(resource);
    await directory.create(recursive: true);
    final destination = await installedFile(resource);
    final partial = File('${destination.path}.download');
    if (await partial.exists()) await partial.delete();

    HttpClientRequest? request;
    IOSink? sink;
    var sinkClosed = false;
    var installed = false;
    try {
      request = await _client.getUrl(url).timeout(connectTimeout);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

      void abortRequest() => request?.abort(const DownloadCancelled());
      cancellationToken?.addListener(abortRequest);
      try {
        _throwIfCancelled(cancellationToken);
        final response = await request.close().timeout(responseTimeout);
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

        sink = partial.openWrite();
        final received = await _copyResponse(
          response: response,
          request: request,
          sink: sink,
          resource: resource,
          cancellationToken: cancellationToken,
          onProgress: onProgress,
        );
        await sink.flush();
        await sink.close();
        sinkClosed = true;

        if (received != resource.sizeBytes) {
          throw DownloadIntegrityException(
            'Downloaded $received bytes; expected ${resource.sizeBytes}.',
          );
        }
        if (!await _matchesHash(partial, resource.sha256)) {
          throw const DownloadIntegrityException(
            'The SHA-256 checksum did not match. Please retry the download.',
          );
        }
        if (await destination.exists()) await destination.delete();
        final result = await partial.rename(destination.path);
        await _writeIntegrityReceipt(resource, received);
        installed = true;
        return result;
      } finally {
        cancellationToken?.removeListener(abortRequest);
      }
    } on TimeoutException catch (error, stackTrace) {
      request?.abort(error, stackTrace);
      rethrow;
    } on DownloadCancelled catch (error, stackTrace) {
      request?.abort(error, stackTrace);
      rethrow;
    } finally {
      if (!sinkClosed) {
        try {
          await sink?.close();
        } on Object {
          // Preserve the original download error; partial data is removed below.
        }
      }
      if (!installed && await partial.exists()) {
        await partial.delete();
      }
    }
  }

  Future<int> _copyResponse({
    required HttpClientResponse response,
    required HttpClientRequest request,
    required IOSink sink,
    required ResourceDescriptor resource,
    required DownloadCancellationToken? cancellationToken,
    required void Function(DownloadProgress progress)? onProgress,
  }) async {
    final done = Completer<int>();
    StreamSubscription<List<int>>? subscription;
    Timer? idleTimer;
    var received = 0;

    void completeError(Object error, [StackTrace? stackTrace]) {
      if (!done.isCompleted) {
        done.completeError(error, stackTrace ?? StackTrace.current);
      }
    }

    void resetIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(idleBodyTimeout, () {
        final error = TimeoutException(
          'The download stopped receiving data.',
          idleBodyTimeout,
        );
        request.abort(error, StackTrace.current);
        unawaited(subscription?.cancel());
        completeError(error);
      });
    }

    void cancelBody() {
      request.abort(const DownloadCancelled());
      unawaited(subscription?.cancel());
      completeError(const DownloadCancelled());
    }

    cancellationToken?.addListener(cancelBody);
    try {
      _throwIfCancelled(cancellationToken);
      resetIdleTimer();
      subscription = response.listen(
        (chunk) {
          resetIdleTimer();
          received += chunk.length;
          if (received > resource.sizeBytes) {
            final error = const DownloadIntegrityException(
              'The download exceeded the expected file size.',
            );
            request.abort(error, StackTrace.current);
            unawaited(subscription?.cancel());
            completeError(error);
            return;
          }
          sink.add(chunk);
          onProgress?.call(
            DownloadProgress(
              receivedBytes: received,
              totalBytes: resource.sizeBytes,
            ),
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          completeError(error, stackTrace);
        },
        onDone: () {
          if (!done.isCompleted) done.complete(received);
        },
        cancelOnError: true,
      );
      return await done.future;
    } finally {
      idleTimer?.cancel();
      cancellationToken?.removeListener(cancelBody);
      await subscription?.cancel();
    }
  }

  void _throwIfCancelled(DownloadCancellationToken? token) {
    if (token?.isCancelled ?? false) {
      throw const DownloadCancelled();
    }
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
