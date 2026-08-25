import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/atomic_file_store.dart';
import 'teaching_context.dart';

class WorkflowContextStore {
  WorkflowContextStore({Future<File> Function()? fileProvider})
      : _fileProvider = fileProvider ?? _defaultFile;

  final Future<File> Function() _fileProvider;

  static Future<File> _defaultFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'preferences', 'workflow_context.v1.json'));
  }

  Future<TeachingContext?> lastFor(String workflow) async {
    final all = await _readAll();
    return all[workflow];
  }

  Future<void> save(String workflow, TeachingContext context) async {
    final all = await _readAll();
    all[workflow] = context;
    final file = await _fileProvider();
    await AtomicFileStore.shared.writeJson(
      file,
      {for (final entry in all.entries) entry.key: entry.value.toJson()},
    );
  }

  Future<Map<String, TeachingContext>> _readAll() async {
    final file = await _fileProvider();
    if (!await file.exists()) return <String, TeachingContext>{};
    try {
      final raw = Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
      return raw.map((key, value) => MapEntry(
            key,
            TeachingContext.fromJson(Map<String, dynamic>.from(value as Map)),
          ));
    } catch (_) {
      await AtomicFileStore.shared.quarantineCorrupt(file);
      return <String, TeachingContext>{};
    }
  }
}
