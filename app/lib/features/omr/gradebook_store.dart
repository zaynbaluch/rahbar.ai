import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/atomic_file_store.dart';
import '../../core/storage/local_store_load.dart';

import 'graded_result.dart';

/// File-backed store for graded sheets: one JSON per result under
/// `<appSupport>/gradebook/`. Small dataset (a class or two), so flat files are
/// simpler and more robust than a codegen'd DB — mirrors LibraryStore.
class GradebookStore {
  GradebookStore({Future<Directory> Function()? supportDirectory})
      : _supportDirectory =
            supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  Future<Directory> _dir() async {
    final base = await _supportDirectory();
    final dir = Directory(p.join(base.path, 'gradebook'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> save(GradedResult r) async {
    final dir = await _dir();
    await AtomicFileStore.shared.writeJson(
      File(p.join(dir.path, '${r.id}.json')),
      r.toJson(),
    );
  }

  /// All graded results, newest first. Used by the existing Results destination.
  Future<List<GradedResult>> listAll() async => (await loadAll()).items;

  Future<LocalStoreLoad<GradedResult>> loadAll() => _load();

  /// All graded results for [testId], newest first.
  Future<List<GradedResult>> listForTest(String testId) async =>
      (await loadForTest(testId)).items;

  Future<LocalStoreLoad<GradedResult>> loadForTest(String testId) =>
      _load(testId: testId);

  Future<LocalStoreLoad<GradedResult>> _load({String? testId}) async {
    final dir = await _dir();
    final out = <GradedResult>[];
    var recoveredFiles = 0;
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          final result = GradedResult.fromJson(
            jsonDecode(await e.readAsString()) as Map<String, dynamic>,
          );
          if (testId == null || result.testId == testId) out.add(result);
        } catch (_) {
          if (await AtomicFileStore.shared.quarantineCorrupt(e) != null) {
            recoveredFiles++;
          }
        }
      }
    }
    out.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return LocalStoreLoad(
      items: out,
      recoveredFiles: recoveredFiles,
    );
  }

  Future<void> delete(String id) async {
    final dir = await _dir();
    final f = File(p.join(dir.path, '$id.json'));
    if (await f.exists()) await f.delete();
  }
}
