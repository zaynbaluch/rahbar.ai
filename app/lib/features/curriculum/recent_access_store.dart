import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/atomic_file_store.dart';

class RecentCurriculumAccess {
  const RecentCurriculumAccess({
    required this.classCode,
    required this.subjectCode,
    required this.topicId,
    required this.topicTitle,
    required this.accessedAtMillis,
  });

  final String classCode;
  final String subjectCode;
  final String topicId;
  final String topicTitle;
  final int accessedAtMillis;

  Map<String, Object?> toJson() => {
        'class_code': classCode,
        'subject_code': subjectCode,
        'topic_id': topicId,
        'topic_title': topicTitle,
        'accessed_at_millis': accessedAtMillis,
      };

  factory RecentCurriculumAccess.fromJson(Map<String, Object?> json) =>
      RecentCurriculumAccess(
        classCode: json['class_code'] as String? ?? '',
        subjectCode: json['subject_code'] as String? ?? '',
        topicId: json['topic_id'] as String? ?? '',
        topicTitle: json['topic_title'] as String? ?? '',
        accessedAtMillis: json['accessed_at_millis'] as int? ?? 0,
      );
}

class RecentAccessStore {
  RecentAccessStore({
    Future<File> Function()? fileProvider,
    int Function()? nowMillis,
  })  : _fileProvider = fileProvider ?? _defaultFile,
        _nowMillis = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const _maxItems = 8;

  final Future<File> Function() _fileProvider;
  final int Function() _nowMillis;

  static Future<File> _defaultFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'preferences', 'recent_curriculum.v1.json'));
  }

  Future<List<RecentCurriculumAccess>> list() async {
    final file = await _fileProvider();
    return _listFrom(file);
  }

  Future<List<RecentCurriculumAccess>> _listFrom(File file) async {
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString()) as List;
      final items = decoded
          .map((item) => RecentCurriculumAccess.fromJson(
                Map<String, Object?>.from(item as Map),
              ))
          .toList();
      items.sort((a, b) => b.accessedAtMillis.compareTo(a.accessedAtMillis));
      return items.take(_maxItems).toList(growable: false);
    } catch (_) {
      await AtomicFileStore.shared.quarantineCorrupt(file);
      return const [];
    }
  }

  Future<void> record({
    required String classCode,
    required String subjectCode,
    required String topicId,
    required String topicTitle,
  }) async {
    final file = await _fileProvider();
    await AtomicFileStore.shared.runExclusive(
      '${file.path}#recent-update',
      () async {
        final items = (await _listFrom(file)).toList();
        items.removeWhere((item) =>
            item.classCode == classCode &&
            item.subjectCode == subjectCode &&
            item.topicId == topicId);
        items.insert(
          0,
          RecentCurriculumAccess(
            classCode: classCode,
            subjectCode: subjectCode,
            topicId: topicId,
            topicTitle: topicTitle,
            accessedAtMillis: _nowMillis(),
          ),
        );
        await AtomicFileStore.shared.writeJson(
          file,
          items.take(_maxItems).map((item) => item.toJson()).toList(),
        );
      },
    );
  }
}
