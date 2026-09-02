import 'omr_diagnostics.dart';

/// Per-question grading outcome.
class OmrQuestion {
  const OmrQuestion({
    required this.number,
    required this.marked,
    required this.correct,
    required this.fill,
    required this.confidence,
    this.reviewed = false,
    OmrDecisionKind? decision,
    this.decisionReason = '',
  }) : decision =
           decision ??
           (marked == null ? OmrDecisionKind.blank : OmrDecisionKind.marked);

  final int number;
  final String? marked;
  final String? correct;
  final double fill;
  final double confidence;
  final bool reviewed;
  final OmrDecisionKind decision;
  final String decisionReason;

  bool get isRight => marked != null && marked == correct;

  Map<String, dynamic> toJson() => {
    'number': number,
    'marked': marked,
    'correct': correct,
    'fill': fill,
    'confidence': confidence,
    'reviewed': reviewed,
    'decision': decision.name,
    'decisionReason': decisionReason,
  };

  factory OmrQuestion.fromJson(Map<String, dynamic> json) => OmrQuestion(
    number: json['number'] as int,
    marked: json['marked'] as String?,
    correct: json['correct'] as String?,
    fill: (json['fill'] as num).toDouble(),
    confidence: (json['confidence'] as num).toDouble(),
    reviewed: json['reviewed'] as bool? ?? false,
    decision: omrDecisionKindFromWire(
      json['decision'],
      marked: json['marked'] as String?,
    ),
    decisionReason: json['decisionReason'] as String? ?? '',
  );
}

/// Result of grading one answer sheet against a test's key.
class OmrResult {
  const OmrResult({
    required this.questions,
    required this.fiducialsFound,
    this.diagnostics,
  });

  final List<OmrQuestion> questions;
  final bool fiducialsFound;
  final OmrDiagnostics? diagnostics;

  int get total => questions.length;
  int get correct => questions.where((question) => question.isRight).length;
  int get blank =>
      questions.where((question) => question.marked == null).length;
  int get needsReview => questions
      .where(
        (question) =>
            !question.reviewed &&
            (question.decision != OmrDecisionKind.marked ||
                question.confidence < 0.20),
      )
      .length;

  Map<String, dynamic> toJson() => {
    'fiducialsFound': fiducialsFound,
    'questions': questions.map((question) => question.toJson()).toList(),
    if (diagnostics != null) 'diagnostics': diagnostics!.toJson(),
  };

  factory OmrResult.fromJson(Map<String, dynamic> json) => OmrResult(
    fiducialsFound: json['fiducialsFound'] as bool,
    diagnostics: json['diagnostics'] == null
        ? null
        : OmrDiagnostics.fromJson(
            Map<String, dynamic>.from(json['diagnostics'] as Map),
          ),
    questions: (json['questions'] as List)
        .map(
          (question) =>
              OmrQuestion.fromJson(Map<String, dynamic>.from(question as Map)),
        )
        .toList(growable: false),
  );

  OmrResult withMark(int questionNumber, String? mark) => OmrResult(
    fiducialsFound: fiducialsFound,
    diagnostics: diagnostics,
    questions: [
      for (final question in questions)
        if (question.number == questionNumber)
          OmrQuestion(
            number: question.number,
            marked: mark,
            correct: question.correct,
            fill: question.fill,
            confidence: question.confidence,
            reviewed: true,
            decision: mark == null
                ? OmrDecisionKind.blank
                : OmrDecisionKind.marked,
            decisionReason: 'teacher reviewed',
          )
        else
          question,
    ],
  );
}
