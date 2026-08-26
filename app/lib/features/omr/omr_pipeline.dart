import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../generation/mcq_parser.dart';
import 'omr_bubble_analysis.dart';
import 'omr_diagnostics.dart';
import 'omr_image_quality.dart';
import 'omr_rectifier.dart';
import 'omr_registration.dart';
import 'omr_result.dart';
import 'omr_template.dart';

abstract final class OmrPipeline {
  static OmrResult scan(img.Image image, McqTest key) {
    final validation = key.validation;
    if (!validation.isReady) {
      throw StateError('Cannot grade an invalid paper: ${validation.summary}');
    }

    final timings = <String, int>{};
    final totalWatch = Stopwatch()..start();
    final stage = Stopwatch()..start();
    final gray = img.grayscale(image);
    final quality = OmrImageQuality.measure(gray);
    timings['quality'] = stage.elapsedMilliseconds;

    final layout = OmrTemplate.layoutFor(key.expectedCount);
    stage
      ..reset()
      ..start();
    final registration = OmrRegistration.detect(gray, layout);
    timings['registration'] = stage.elapsedMilliseconds;
    final answers = {
      for (final question in key.questions) question.number: question.answer,
    };

    if (!registration.success) {
      timings['total'] = totalWatch.elapsedMilliseconds;
      final diagnostics = OmrDiagnostics(
        status: OmrScanStatus.rejected,
        failureCode: registration.failureCode,
        sourceWidth: gray.width,
        sourceHeight: gray.height,
        meanLuminance: quality.meanLuminance,
        darkClipFraction: quality.darkClipFraction,
        lightClipFraction: quality.lightClipFraction,
        blurVariance: quality.blurVariance,
        warnings: quality.warnings,
        markerCandidateCount: registration.candidateCount,
        registrationScore: registration.score,
        registrationNote: registration.note,
        stageTimingsMs: timings,
      );
      return OmrResult(
        fiducialsFound: false,
        diagnostics: diagnostics,
        questions: [
          for (final question in key.questions)
            OmrQuestion(
              number: question.number,
              marked: null,
              correct: answers[question.number],
              fill: 0,
              confidence: 0,
              decision: OmrDecisionKind.blank,
              decisionReason: 'scan rejected before bubble analysis',
            ),
        ],
      );
    }

    stage
      ..reset()
      ..start();
    final canonical = OmrRectifier.rectify(
      gray,
      registration.fiducials,
      layout,
    );
    timings['rectification'] = stage.elapsedMilliseconds;

    stage
      ..reset()
      ..start();
    final observationsByQuestion = <int, List<OmrBubbleDiagnostic>>{};
    final allObservations = <OmrBubbleDiagnostic>[];
    for (final question in key.questions) {
      final row = <OmrBubbleDiagnostic>[];
      for (var option = 0; option < OmrTemplate.options; option++) {
        final observation = OmrBubbleSampler.sample(
          canonical,
          layout,
          question.number,
          option,
        );
        row.add(observation);
        allObservations.add(observation);
      }
      observationsByQuestion[question.number] = row;
    }
    final calibration = OmrSheetCalibration.fromObservations(allObservations);
    final questions = <OmrQuestion>[];
    final rowDiagnostics = <OmrRowDiagnostic>[];
    for (final question in key.questions) {
      final bubbles = observationsByQuestion[question.number]!;
      final decision = OmrRowClassifier.classify(bubbles, calibration);
      questions.add(
        OmrQuestion(
          number: question.number,
          marked: decision.marked,
          correct: answers[question.number],
          fill: decision.fill,
          confidence: decision.confidence,
          decision: decision.decision,
          decisionReason: decision.reason,
        ),
      );
      rowDiagnostics.add(
        OmrRowDiagnostic(
          questionNumber: question.number,
          bubbles: bubbles,
          decision: decision.decision,
          marked: decision.marked,
          confidence: decision.confidence,
          reason: decision.reason,
        ),
      );
    }
    timings['analysis'] = stage.elapsedMilliseconds;

    final warnings = [...quality.warnings];
    if (registration.score < .60) {
      warnings.add('registration confidence is relatively low');
    }
    final uncertain = questions
        .where(
          (question) =>
              question.decision != OmrDecisionKind.marked ||
              question.confidence < .20,
        )
        .length;
    if (uncertain > math.max(2, (questions.length * .35).floor())) {
      warnings.add('many rows need teacher review');
    }
    timings['total'] = totalWatch.elapsedMilliseconds;

    final diagnostics = OmrDiagnostics(
      status: OmrScanStatus.complete,
      failureCode: OmrFailureCode.none,
      sourceWidth: gray.width,
      sourceHeight: gray.height,
      canonicalWidth: canonical.width,
      canonicalHeight: canonical.height,
      meanLuminance: quality.meanLuminance,
      darkClipFraction: quality.darkClipFraction,
      lightClipFraction: quality.lightClipFraction,
      blurVariance: quality.blurVariance,
      warnings: warnings,
      markerCandidateCount: registration.candidateCount,
      fiducials: registration.fiducials,
      registrationScore: registration.score,
      registrationNote: registration.note,
      stageTimingsMs: timings,
      blankBaseline: calibration.blankBaseline,
      blankMad: calibration.blankMad,
      markThreshold: calibration.markThreshold,
      rows: rowDiagnostics,
    );

    return OmrResult(
      questions: questions,
      fiducialsFound: true,
      diagnostics: diagnostics,
    );
  }
}
