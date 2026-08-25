import 'omr_grader.dart';

/// One graded answer sheet, persisted so a teacher can grade a whole class and
/// keep a record. Keyed by the test ID (the same ID printed on the sheet). The
/// student name is entered by the teacher — OMR reads bubbles, not handwriting.
class GradedResult {
  const GradedResult({
    required this.id,
    required this.testId,
    required this.testTopic,
    required this.studentName,
    required this.correct,
    required this.total,
    required this.marks,
    required this.correctAnswers,
    required this.createdAtMillis,
    this.schemaVersion = 2,
  });

  final String id;
  final String testId;
  final String testTopic;
  final String studentName;
  final int correct;
  final int total;

  /// Per-question marked options joined by '|', '' = blank (e.g. "A|C||B").
  final String marks;
  /// Immutable answer-key snapshot used when this result was confirmed.
  final String correctAnswers;
  final int createdAtMillis;
  final int schemaVersion;

  int get pct => total == 0 ? 0 : (100 * correct / total).round();
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMillis);

  static GradedResult fromGrading({
    required String testId,
    required String testTopic,
    required String studentName,
    required OmrResult result,
  }) {
    return GradedResult(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      testId: testId,
      testTopic: testTopic,
      studentName: studentName,
      correct: result.correct,
      total: result.total,
      marks: result.questions.map((q) => q.marked ?? '').join('|'),
      correctAnswers: result.questions.map((q) => q.correct ?? '').join('|'),
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'testId': testId,
        'testTopic': testTopic,
        'studentName': studentName,
        'correct': correct,
        'total': total,
        'marks': marks,
        'correctAnswers': correctAnswers,
        'createdAtMillis': createdAtMillis,
        'schemaVersion': schemaVersion,
      };

  factory GradedResult.fromJson(Map<String, dynamic> j) => GradedResult(
        id: j['id'] as String,
        testId: j['testId'] as String? ?? '',
        testTopic: j['testTopic'] as String? ?? '',
        studentName: j['studentName'] as String? ?? '',
        correct: j['correct'] as int? ?? 0,
        total: j['total'] as int? ?? 0,
        marks: j['marks'] as String? ?? '',
        correctAnswers: j['correctAnswers'] as String? ?? '',
        createdAtMillis: j['createdAtMillis'] as int? ?? 0,
        schemaVersion: j['schemaVersion'] as int? ?? 1,
      );
}
