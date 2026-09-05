import 'dart:convert';

import '../generation/lesson_plan.dart';
import '../generation/mcq_parser.dart';
import '../curriculum/teaching_context.dart';

enum SavedContentSource { curriculumPack, customAi, legacy }

String _sourceWireName(SavedContentSource source) => switch (source) {
  SavedContentSource.curriculumPack => 'curriculum_pack',
  SavedContentSource.customAi => 'custom_ai',
  SavedContentSource.legacy => 'legacy',
};

SavedContentSource _sourceFromWire(String? value) => switch (value) {
  'curriculum_pack' => SavedContentSource.curriculumPack,
  'custom_ai' => SavedContentSource.customAi,
  _ => SavedContentSource.legacy,
};

/// A test or lesson plan saved to the on-device library.
///
/// [source] is stored explicitly so structured custom AI output is never shown as
/// verified curriculum content. Older entries without a source are treated as
/// legacy unless their content-pack topic ID makes the origin unambiguous.
class SavedTest {
  const SavedTest({
    required this.id,
    required this.kind,
    required this.topic,
    required this.createdAtMillis,
    this.source = SavedContentSource.legacy,
    this.rawOutput = '',
    this.contentJson,
    this.topicId,
    this.excerptTitles = const [],
    this.teachingContext,
  });

  final String id; // unique (timestamp-based)
  final String kind; // 'mcq' | 'lesson'
  final String topic;
  final int createdAtMillis;
  final SavedContentSource source;

  final String rawOutput; // SLM path: the model's text, re-parsed on open
  final Map<String, dynamic>?
  contentJson; // structured content, regardless of origin
  final String? topicId; // content-pack topic, when it came from the bank
  final List<String> excerptTitles;
  final TeachingContext? teachingContext;

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtMillis);

  bool get fromPack => source == SavedContentSource.curriculumPack;
  bool get fromCustomAi => source == SavedContentSource.customAi;

  /// The structured MCQ test (kind == 'mcq').
  McqTest toMcqTest() {
    if (contentJson == null) {
      return McqParser.parse(rawOutput, topic: topic, testId: id);
    }
    final json = Map<String, dynamic>.from(contentJson!);
    json.putIfAbsent('id', () => id);
    if (!json.containsKey('expectedCount') && !fromPack) {
      // The app's historical custom-generation contract requested ten questions.
      // Do not let a truncated legacy model response become printable merely
      // because older JSON did not record the expected count.
      json['expectedCount'] = 10;
    }
    return McqTest.fromJson(json);
  }

  /// The structured lesson plan (kind == 'lesson'). New SLM-generated plans are
  /// parsed before saving; older library entries may still return null and use the
  /// raw-text recovery view.
  LessonPlan? toLessonPlan() =>
      contentJson == null ? null : LessonPlan.fromJson(contentJson!);

  SavedTest copyWith({Map<String, dynamic>? contentJson}) => SavedTest(
    id: id,
    kind: kind,
    topic: topic,
    createdAtMillis: createdAtMillis,
    source: source,
    rawOutput: rawOutput,
    contentJson: contentJson ?? this.contentJson,
    topicId: topicId,
    excerptTitles: excerptTitles,
    teachingContext: teachingContext,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'topic': topic,
    'createdAtMillis': createdAtMillis,
    'source': _sourceWireName(source),
    'rawOutput': rawOutput,
    if (contentJson != null) 'contentJson': jsonEncode(contentJson),
    if (topicId != null) 'topicId': topicId,
    'excerptTitles': excerptTitles,
    if (teachingContext != null) 'teachingContext': teachingContext!.toJson(),
  };

  factory SavedTest.fromJson(Map<String, dynamic> j) {
    final raw = j['contentJson'];
    final contentJson = raw == null
        ? null
        : (raw is String
              ? jsonDecode(raw) as Map<String, dynamic>
              : Map<String, dynamic>.from(raw as Map));
    final topicId = j['topicId'] as String?;
    final savedSource = j['source'] as String?;
    final source =
        savedSource == null &&
            contentJson != null &&
            topicId != null &&
            topicId.trim().isNotEmpty
        ? SavedContentSource.curriculumPack
        : _sourceFromWire(savedSource);
    return SavedTest(
      id: j['id'] as String,
      kind: j['kind'] as String? ?? 'mcq',
      topic: j['topic'] as String? ?? '',
      createdAtMillis: j['createdAtMillis'] as int? ?? 0,
      source: source,
      rawOutput: j['rawOutput'] as String? ?? '',
      contentJson: contentJson,
      topicId: topicId,
      excerptTitles:
          (j['excerptTitles'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      teachingContext: j['teachingContext'] == null
          ? null
          : TeachingContext.fromJson(
              Map<String, dynamic>.from(j['teachingContext'] as Map),
            ),
    );
  }
}
