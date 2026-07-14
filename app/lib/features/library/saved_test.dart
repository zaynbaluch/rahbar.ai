import 'dart:convert';

import '../generation/lesson_plan.dart';
import '../generation/mcq_parser.dart';

/// A test or lesson plan saved to the on-device library.
///
/// Two kinds of content end up here and they persist differently:
///
///  * **From the content pack** (the normal path, ADR-008) — the test was *sampled* from
///    the verified item bank and the plan *assembled* from section variants, so there is no
///    raw model text to re-parse. We store the structured object in [contentJson]. This also
///    keeps the answer key stable: re-parsing is not involved, so what was printed is exactly
///    what the OMR grader scores against.
///  * **From the on-device SLM** (the escape hatch, for topics outside the pack) — we keep
///    the model's [rawOutput] and re-parse on open, as before.
///
/// [contentJson] wins when present; [rawOutput] is the fallback, so libraries written by
/// earlier builds still open.
class SavedTest {
  const SavedTest({
    required this.id,
    required this.kind,
    required this.topic,
    required this.createdAtMillis,
    this.rawOutput = '',
    this.contentJson,
    this.topicId,
    this.excerptTitles = const [],
  });

  final String id; // unique (timestamp-based)
  final String kind; // 'mcq' | 'lesson'
  final String topic;
  final int createdAtMillis;

  final String rawOutput; // SLM path: the model's text, re-parsed on open
  final Map<String, dynamic>? contentJson; // pack path: the structured object
  final String? topicId; // content-pack topic, when it came from the bank
  final List<String> excerptTitles;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMillis);

  bool get fromPack => contentJson != null;

  /// The structured MCQ test (kind == 'mcq').
  McqTest toMcqTest() => contentJson != null
      ? McqTest.fromJson(contentJson!)
      : McqParser.parse(rawOutput, topic: topic);

  /// The structured lesson plan (kind == 'lesson'). Null for SLM-generated plans, which
  /// are an unstructured blob and are rendered as text.
  LessonPlan? toLessonPlan() =>
      contentJson == null ? null : LessonPlan.fromJson(contentJson!);

  SavedTest copyWith({Map<String, dynamic>? contentJson}) => SavedTest(
        id: id,
        kind: kind,
        topic: topic,
        createdAtMillis: createdAtMillis,
        rawOutput: rawOutput,
        contentJson: contentJson ?? this.contentJson,
        topicId: topicId,
        excerptTitles: excerptTitles,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'topic': topic,
        'createdAtMillis': createdAtMillis,
        'rawOutput': rawOutput,
        if (contentJson != null) 'contentJson': jsonEncode(contentJson),
        if (topicId != null) 'topicId': topicId,
        'excerptTitles': excerptTitles,
      };

  factory SavedTest.fromJson(Map<String, dynamic> j) {
    final raw = j['contentJson'];
    return SavedTest(
      id: j['id'] as String,
      kind: j['kind'] as String? ?? 'mcq',
      topic: j['topic'] as String? ?? '',
      createdAtMillis: j['createdAtMillis'] as int? ?? 0,
      rawOutput: j['rawOutput'] as String? ?? '',
      contentJson: raw == null
          ? null
          : (raw is String
              ? jsonDecode(raw) as Map<String, dynamic>
              : Map<String, dynamic>.from(raw as Map)),
      topicId: j['topicId'] as String?,
      excerptTitles:
          (j['excerptTitles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
