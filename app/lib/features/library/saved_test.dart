import '../generation/mcq_parser.dart';

/// A generated test persisted to the on-device library so the (multi-minute)
/// generation cost is paid once. We store the raw model output and re-parse it on
/// open — keeping the stored form small and forward-compatible if the parser
/// improves. `excerptTitles` records what it was grounded in, for display.
class SavedTest {
  const SavedTest({
    required this.id,
    required this.kind,
    required this.topic,
    required this.rawOutput,
    required this.createdAtMillis,
    this.excerptTitles = const [],
  });

  final String id; // unique (timestamp-based)
  final String kind; // 'mcq' | 'lesson'
  final String topic;
  final String rawOutput; // the model's text, re-parsed on open
  final int createdAtMillis;
  final List<String> excerptTitles;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMillis);

  /// Parse the stored MCQ output into a structured test (MCQ kind only).
  McqTest toMcqTest() => McqParser.parse(rawOutput, topic: topic);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'topic': topic,
        'rawOutput': rawOutput,
        'createdAtMillis': createdAtMillis,
        'excerptTitles': excerptTitles,
      };

  factory SavedTest.fromJson(Map<String, dynamic> j) => SavedTest(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'mcq',
        topic: j['topic'] as String? ?? '',
        rawOutput: j['rawOutput'] as String? ?? '',
        createdAtMillis: j['createdAtMillis'] as int? ?? 0,
        excerptTitles:
            (j['excerptTitles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}
