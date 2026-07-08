import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'saved_test.dart';

/// File-backed store for saved tests: one JSON file per test under
/// `<appSupport>/library/`. Small dataset (a handful of tests), so flat files are
/// simpler and more robust than a codegen'd DB for the MVP; can move to drift
/// later if history/search/sync grow.
class LibraryStore {
  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'library'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> save(SavedTest test) async {
    final dir = await _dir();
    final f = File(p.join(dir.path, '${test.id}.json'));
    await f.writeAsString(jsonEncode(test.toJson()), flush: true);
  }

  /// All saved tests, newest first.
  Future<List<SavedTest>> list() async {
    final dir = await _dir();
    final tests = <SavedTest>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          tests.add(SavedTest.fromJson(
              jsonDecode(await e.readAsString()) as Map<String, dynamic>));
        } catch (_) {
          // Skip a corrupt file rather than break the whole library.
        }
      }
    }
    tests.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
    return tests;
  }

  Future<void> delete(String id) async {
    final dir = await _dir();
    final f = File(p.join(dir.path, '$id.json'));
    if (await f.exists()) await f.delete();
  }
}
