import 'package:bayaz_ai/features/omr/omr_diagnostics.dart';
import 'package:bayaz_ai/features/omr/omr_grader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostics survive JSON and produce a copyable report', () {
    const diagnostics = OmrDiagnostics(
      status: OmrScanStatus.complete,
      failureCode: OmrFailureCode.none,
      sourceWidth: 1080,
      sourceHeight: 1440,
      canonicalWidth: 820,
      canonicalHeight: 1160,
      meanLuminance: 221.4,
      darkClipFraction: .01,
      lightClipFraction: .72,
      blurVariance: 42.5,
      warnings: ['soft image'],
      markerCandidateCount: 7,
      fiducials: [
        OmrPoint(100, 120),
        OmrPoint(900, 130),
        OmrPoint(890, 1300),
        OmrPoint(110, 1290),
      ],
      registrationScore: .91,
      templateMatchScore: .94,
      templateMatchedBubbles: 39,
      templateExpectedBubbles: 40,
      templateBorderCoverage: .92,
      templateMinimumSideBorderCoverage: .88,
      templateNote: 'aligned',
      blankBaseline: .03,
      blankMad: .01,
      markThreshold: .14,
      rows: [
        OmrRowDiagnostic(
          questionNumber: 1,
          bubbles: [
            OmrBubbleDiagnostic(
              option: 'A',
              interiorDarkness: .05,
              backgroundDarkness: .03,
              localContrast: .02,
              darkPixelDensity: .01,
              score: .02,
            ),
            OmrBubbleDiagnostic(
              option: 'B',
              interiorDarkness: .7,
              backgroundDarkness: .04,
              localContrast: .66,
              darkPixelDensity: .8,
              score: .71,
            ),
          ],
          decision: OmrDecisionKind.marked,
          marked: 'B',
          confidence: .88,
          reason: 'clear winner',
        ),
      ],
    );

    final restored = OmrDiagnostics.fromJson(diagnostics.toJson());
    expect(restored.registrationScore, closeTo(.91, 1e-9));
    expect(restored.templateBorderCoverage, closeTo(.92, 1e-9));
    expect(restored.templateMinimumSideBorderCoverage, closeTo(.88, 1e-9));
    expect(restored.rows.single.marked, 'B');
    expect(restored.rows.single.bubbles[1].score, closeTo(.71, 1e-9));

    final report = restored.toReport();
    expect(report, contains('status=complete'));
    expect(report, contains('markers candidates=7'));
    expect(report, contains('border=0.920 minSide=0.880'));
    expect(report, contains('Q1 marked=B'));
    expect(report, contains('B=0.710'));
  });

  test('old grading JSON without diagnostics still decodes', () {
    final restored = OmrResult.fromJson({
      'fiducialsFound': true,
      'questions': [
        {
          'number': 1,
          'marked': null,
          'correct': 'A',
          'fill': .12,
          'confidence': .03,
          'reviewed': false,
        },
      ],
    });

    expect(restored.diagnostics, isNull);
    expect(restored.questions.single.decision, OmrDecisionKind.blank);
    expect(restored.needsReview, 1);
  });

  test('ambiguous decisions remain reviewable after serialization', () {
    const result = OmrResult(
      fiducialsFound: true,
      questions: [
        OmrQuestion(
          number: 1,
          marked: null,
          correct: 'C',
          fill: .55,
          confidence: .04,
          decision: OmrDecisionKind.ambiguous,
          decisionReason: 'two competitive marks',
        ),
      ],
    );

    final restored = OmrResult.fromJson(result.toJson());
    expect(restored.questions.single.decision, OmrDecisionKind.ambiguous);
    expect(restored.questions.single.decisionReason, 'two competitive marks');
    expect(restored.needsReview, 1);
  });
}
