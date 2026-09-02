import 'dart:async';
import 'dart:io';

import 'package:bayaz_ai/features/resources/download_manager.dart';
import 'package:bayaz_ai/features/resources/resource_manifest.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('cancellation token notifies current listeners once', () {
    final token = DownloadCancellationToken();
    var calls = 0;
    void listener() => calls += 1;

    token.addListener(listener);
    token.cancel();
    token.cancel();

    expect(token.isCancelled, isTrue);
    expect(calls, 1);
  });

  test('cancellation token immediately notifies late listeners', () {
    final token = DownloadCancellationToken()..cancel();
    var calls = 0;

    token.addListener(() => calls += 1);

    expect(calls, 1);
  });

  test('removed cancellation listeners are not called', () {
    final token = DownloadCancellationToken();
    var calls = 0;
    void listener() => calls += 1;

    token.addListener(listener);
    token.removeListener(listener);
    token.cancel();

    expect(calls, 0);
  });

  test(
    'cancelling a stalled body aborts and removes the partial file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bayaz-download-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final request = _FakeRequest(_FakeResponse(body.stream));
      final manager = _TestDownloadManager(
        client: _FakeClient(request),
        directory: directory,
        idleBodyTimeout: const Duration(minutes: 1),
      );
      final token = DownloadCancellationToken();
      final progress = Completer<void>();
      final resource = _resource(
        sizeBytes: 4,
        sha256Value: sha256.convert(const [1, 2, 3, 4]).toString(),
      );

      final download = manager.download(
        resource,
        cancellationToken: token,
        onProgress: (_) {
          if (!progress.isCompleted) progress.complete();
        },
      );
      body.add(const [1, 2]);
      await progress.future;
      token.cancel();

      await expectLater(download, throwsA(isA<DownloadCancelled>()));
      expect(request.aborted, isTrue);
      expect(
        File('${directory.path}/${resource.fileName}.download').existsSync(),
        isFalse,
      );
    },
  );

  test('integrity failures remove the partial file', () async {
    final directory = await Directory.systemTemp.createTemp('bayaz-download-');
    addTearDown(() => directory.delete(recursive: true));
    final response = _FakeResponse(Stream<List<int>>.value(const [1, 2, 3]));
    final manager = _TestDownloadManager(
      client: _FakeClient(_FakeRequest(response)),
      directory: directory,
    );
    final resource = _resource(
      sizeBytes: 3,
      sha256Value: List.filled(64, '0').join(),
    );

    await expectLater(
      manager.download(resource),
      throwsA(isA<DownloadIntegrityException>()),
    );
    expect(
      File('${directory.path}/${resource.fileName}.download').existsSync(),
      isFalse,
    );
    expect(
      File('${directory.path}/${resource.fileName}').existsSync(),
      isFalse,
    );
  });

  test('verified resources persist an integrity receipt', () async {
    final directory = await Directory.systemTemp.createTemp('bayaz-integrity-');
    addTearDown(() => directory.delete(recursive: true));
    const bytes = [1, 2, 3];
    final resource = _resource(
      sizeBytes: bytes.length,
      sha256Value: sha256.convert(bytes).toString(),
    );
    final manager = _TestDownloadManager(
      client: _FakeClient(_FakeRequest(_FakeResponse(const Stream.empty()))),
      directory: directory,
    );
    final file = File(p.join(directory.path, resource.fileName));
    await file.writeAsBytes(bytes, flush: true);

    expect(await manager.verifyIntegrity(resource), isTrue);

    final receipt = File(p.join(directory.path, '.integrity.receipt.json'));
    expect(receipt.existsSync(), isTrue);
    expect(await manager.verifyIntegrity(resource), isTrue);

    await file.writeAsBytes([...bytes, 4], flush: true);
    expect(await manager.verifyIntegrity(resource), isFalse);
  });

  test('verified downloads are renamed into place', () async {
    final directory = await Directory.systemTemp.createTemp('bayaz-download-');
    addTearDown(() => directory.delete(recursive: true));
    const bytes = [1, 2, 3];
    final response = _FakeResponse(Stream<List<int>>.value(bytes));
    final manager = _TestDownloadManager(
      client: _FakeClient(_FakeRequest(response)),
      directory: directory,
    );
    final resource = _resource(
      sizeBytes: bytes.length,
      sha256Value: sha256.convert(bytes).toString(),
    );

    final file = await manager.download(resource);

    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), bytes);
    expect(File('${file.path}.download').existsSync(), isFalse);
  });
}

ResourceDescriptor _resource({
  required int sizeBytes,
  required String sha256Value,
}) => ResourceDescriptor(
  id: 'model.test.download',
  kind: ResourceKind.languageModel,
  version: '1.0.0',
  displayName: 'Test model',
  fileName: 'model.gguf',
  sizeBytes: sizeBytes,
  sha256: sha256Value,
  required: false,
  licenseName: 'Test',
  licenseUrl: 'https://example.com/license',
  downloadUrl: Uri.parse('https://example.com/model.gguf'),
);

class _TestDownloadManager extends ResourceDownloadManager {
  _TestDownloadManager({
    required super.client,
    required this.directory,
    super.idleBodyTimeout,
  });

  final Directory directory;

  @override
  Future<Directory> resourceDirectory(ResourceDescriptor resource) async =>
      directory;
}

class _FakeClient implements HttpClient {
  _FakeClient(this.request);

  final _FakeRequest request;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => request;

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.response);

  final HttpClientResponse response;
  final HttpHeaders _headers = _FakeHeaders();
  bool aborted = false;

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.stream);

  final Stream<List<int>> stream;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
