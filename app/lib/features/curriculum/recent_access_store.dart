import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  static const _maxItems = 8;

  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'preferences', 'recent_curriculum.v1.json'));
  }

  Future<List<RecentCurriculumAccess>> list() async {
    final file = await _file();
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
      return const [];
    }
  }

  Future<void> record({
    required String classCode,
    required String subjectCode,
    required String topicId,
    required String topicTitle,
  }) async {
    final items = (await list()).toList();
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
        accessedAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(items.take(_maxItems).map((item) => item.toJson()).toList()),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
