import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/atomic_file_store.dart';

import 'graded_result.dart';

/// File-backed store for graded sheets: one JSON per result under
/// `<appSupport>/gradebook/`. Small dataset (a class or two), so flat files are
/// simpler and more robust than a codegen'd DB — mirrors LibraryStore.
class GradebookStore {
  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
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
  Future<List<GradedResult>> listAll() async {
    final dir = await _dir();
    final out = <GradedResult>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          out.add(GradedResult.fromJson(
              jsonDecode(await e.readAsString()) as Map<String, dynamic>));
        } catch (_) {
          await AtomicFileStore.shared.quarantineCorrupt(e);
        }
      }
    }
    out.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return out;
  }

  /// All graded results for [testId], newest first.
  Future<List<GradedResult>> listForTest(String testId) async {
    final dir = await _dir();
    final out = <GradedResult>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          final r = GradedResult.fromJson(
              jsonDecode(await e.readAsString()) as Map<String, dynamic>);
          if (r.testId == testId) out.add(r);
        } catch (_) {
          await AtomicFileStore.shared.quarantineCorrupt(e);
        }
      }
    }
    out.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return out;
  }

  Future<void> delete(String id) async {
    final dir = await _dir();
    final f = File(p.join(dir.path, '$id.json'));
    if (await f.exists()) await f.delete();
  }
}
