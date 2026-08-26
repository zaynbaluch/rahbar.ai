import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'omr_diagnostics.dart';
import 'omr_template.dart';

abstract final class OmrBubbleSampler {
  static OmrBubbleDiagnostic sample(
    img.Image canonical,
    OmrLayout layout,
    int questionNumber,
    int optionIndex,
  ) {
    final (u, v) = layout.bubbleNorm(questionNumber, optionIndex);
    final cx = (u * (canonical.width - 1)).round();
    final cy = (v * (canonical.height - 1)).round();
    final printedRadius = layout.bubbleR / layout.boxW * canonical.width;
    final innerRadius = math.max(2, (printedRadius * .52).round());
    final ringInner = math.max(innerRadius + 2, (printedRadius * 1.18).round());
    final ringOuter = math.max(ringInner + 2, (printedRadius * 1.55).round());

    double interiorDarkSum = 0;
    var interiorCount = 0;
    double backgroundDarkSum = 0;
    var backgroundCount = 0;
    final interiorValues = <double>[];
    for (var dy = -ringOuter; dy <= ringOuter; dy++) {
      for (var dx = -ringOuter; dx <= ringOuter; dx++) {
        final x = cx + dx;
        final y = cy + dy;
        if (x < 0 || y < 0 || x >= canonical.width || y >= canonical.height) {
          continue;
        }
        final distance2 = dx * dx + dy * dy;
        final luminance = canonical.getPixel(x, y).luminance.toDouble();
        final darkness = (255 - luminance) / 255.0;
        if (distance2 <= innerRadius * innerRadius) {
          interiorDarkSum += darkness;
          interiorCount++;
          interiorValues.add(luminance);
        } else if (distance2 >= ringInner * ringInner &&
            distance2 <= ringOuter * ringOuter) {
          backgroundDarkSum += darkness;
          backgroundCount++;
        }
      }
    }

    final interiorDarkness = interiorCount == 0
        ? 0.0
        : interiorDarkSum / interiorCount;
    final backgroundDarkness = backgroundCount == 0
        ? 0.0
        : backgroundDarkSum / backgroundCount;
    final localContrast = (interiorDarkness - backgroundDarkness)
        .clamp(0.0, 1.0)
        .toDouble();
    final backgroundLuminance = 255 * (1 - backgroundDarkness);
    final darkCutoff = (backgroundLuminance - 55).clamp(35.0, 220.0);
    final darkPixels = interiorValues
        .where((value) => value < darkCutoff)
        .length;
    final density = interiorValues.isEmpty
        ? 0.0
        : darkPixels / interiorValues.length;
    final score = (localContrast * .65 + density * .35)
        .clamp(0.0, 1.0)
        .toDouble();

    return OmrBubbleDiagnostic(
      option: String.fromCharCode(65 + optionIndex),
      interiorDarkness: interiorDarkness,
      backgroundDarkness: backgroundDarkness,
      localContrast: localContrast,
      darkPixelDensity: density.toDouble(),
      score: score,
    );
  }
}

class OmrSheetCalibration {
  const OmrSheetCalibration({
    required this.blankBaseline,
    required this.blankMad,
    required this.markThreshold,
  });

  final double blankBaseline;
  final double blankMad;
  final double markThreshold;

  factory OmrSheetCalibration.fromObservations(
    List<OmrBubbleDiagnostic> observations,
  ) {
    if (observations.isEmpty) {
      return const OmrSheetCalibration(
        blankBaseline: 0,
        blankMad: 0,
        markThreshold: .14,
      );
    }
    final scores = observations.map((bubble) => bubble.score).toList()..sort();
    final blankCount = math.max(1, (scores.length * .65).ceil());
    final blankPool = scores.take(blankCount).toList(growable: false);
    final baseline = _median(blankPool);
    final deviations =
        blankPool.map((score) => (score - baseline).abs()).toList()..sort();
    final mad = _median(deviations);
    final threshold = (baseline + math.max(.09, mad * 6))
        .clamp(.10, .32)
        .toDouble();
    return OmrSheetCalibration(
      blankBaseline: baseline,
      blankMad: mad,
      markThreshold: threshold,
    );
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }
}

class OmrRowDecision {
  const OmrRowDecision({
    required this.decision,
    required this.marked,
    required this.confidence,
    required this.fill,
    required this.reason,
  });

  final OmrDecisionKind decision;
  final String? marked;
  final double confidence;
  final double fill;
  final String reason;
}

abstract final class OmrRowClassifier {
  static OmrRowDecision classify(
    List<OmrBubbleDiagnostic> bubbles,
    OmrSheetCalibration calibration,
  ) {
    if (bubbles.isEmpty) {
      return const OmrRowDecision(
        decision: OmrDecisionKind.blank,
        marked: null,
        confidence: 0,
        fill: 0,
        reason: 'no bubble observations',
      );
    }
    final ranked = [...bubbles]..sort((a, b) => b.score.compareTo(a.score));
    final best = ranked.first;
    final second = ranked.length > 1 ? ranked[1] : null;
    final secondScore = second?.score ?? 0;
    final margin = (best.score - secondScore).clamp(0.0, 1.0).toDouble();
    final threshold = calibration.markThreshold;

    if (best.score < threshold) {
      final confidence = threshold <= 0
          ? 1.0
          : ((threshold - best.score) / threshold).clamp(0.0, 1.0).toDouble();
      return OmrRowDecision(
        decision: OmrDecisionKind.blank,
        marked: null,
        confidence: confidence,
        fill: best.score,
        reason: 'below calibrated threshold',
      );
    }
    if (secondScore >= threshold) {
      return OmrRowDecision(
        decision: OmrDecisionKind.ambiguous,
        marked: null,
        confidence: margin,
        fill: best.score,
        reason: 'multiple bubbles above threshold',
      );
    }
    final minimumMargin = math.max(.055, threshold * .45);
    if (margin < minimumMargin) {
      return OmrRowDecision(
        decision: OmrDecisionKind.ambiguous,
        marked: null,
        confidence: margin,
        fill: best.score,
        reason: 'winner margin too small',
      );
    }

    final strengthConfidence = ((best.score - threshold) / .25)
        .clamp(0.0, 1.0)
        .toDouble();
    final marginConfidence = (margin / .20).clamp(0.0, 1.0).toDouble();
    final confidence = math.min(strengthConfidence, marginConfidence);
    return OmrRowDecision(
      decision: OmrDecisionKind.marked,
      marked: best.option,
      confidence: confidence,
      fill: best.score,
      reason: confidence < .20 ? 'low-strength winner' : 'clear winner',
    );
  }
}
