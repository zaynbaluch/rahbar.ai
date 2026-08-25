import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/atomic_file_store.dart';

class RecentWorkReference {
  const RecentWorkReference({required this.type, required this.id});
  final String type;
  final String id;

  Map<String, Object?> toJson() => {'type': type, 'id': id};

  factory RecentWorkReference.fromJson(Map<String, dynamic> json) =>
      RecentWorkReference(
        type: json['type'] as String? ?? '',
        id: json['id'] as String? ?? '',
      );
}

class RecentWorkStore {
  RecentWorkStore({Future<File> Function()? fileProvider})
      : _fileProvider = fileProvider ?? _defaultFile;

  final Future<File> Function() _fileProvider;

  static Future<File> _defaultFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'preferences', 'recent_work.v1.json'));
  }

  Future<RecentWorkReference?> current() async {
    final file = await _fileProvider();
    if (!await file.exists()) return null;
    try {
      return RecentWorkReference.fromJson(
        Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map),
      );
    } catch (_) {
      await AtomicFileStore.shared.quarantineCorrupt(file);
      return null;
    }
  }

  Future<void> update(RecentWorkReference reference) async {
    final file = await _fileProvider();
    await AtomicFileStore.shared.writeJson(file, reference.toJson());
  }

  Future<void> clear() async {
    final file = await _fileProvider();
    if (await file.exists()) await file.delete();
  }
}
