import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Serializes access per destination path and publishes complete files with a
/// same-directory rename, so readers see either the old file or the new file.
class AtomicFileStore {
  AtomicFileStore._();

  static final AtomicFileStore shared = AtomicFileStore._();

  final Map<String, Future<void>> _tails = {};
  int _temporaryId = 0;

  Future<T> runExclusive<T>(
    String path,
    Future<T> Function() action,
  ) {
    final previous = _tails[path] ?? Future<void>.value();
    final result = Completer<T>();
    late final Future<void> tail;
    tail = previous.catchError((_) {}).then((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    }).whenComplete(() {
      if (identical(_tails[path], tail)) _tails.remove(path);
    });
    _tails[path] = tail;
    return result.future;
  }

  Future<void> writeJson(File file, Object? value) => runExclusive(
        file.path,
        () => _writeString(file, jsonEncode(value)),
      );

  Future<void> writeString(File file, String value) => runExclusive(
        file.path,
        () => _writeString(file, value),
      );

  Future<void> _writeString(File file, String value) async {
    await file.parent.create(recursive: true);
    final id = _temporaryId++;
    final temporary = File(p.join(
      file.parent.path,
      '.${p.basename(file.path)}.${DateTime.now().microsecondsSinceEpoch}.$id.tmp',
    ));
    try {
      await temporary.writeAsString(value, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<File?> quarantineCorrupt(File file) => runExclusive(
        file.path,
        () async {
          if (!await file.exists()) return null;
          final quarantined = File(
            '${file.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}',
          );
          return file.rename(quarantined.path);
        },
      );
}
