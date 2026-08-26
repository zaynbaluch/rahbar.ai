import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'omr_template.dart';

class OmrTemplateMatchResult {
  const OmrTemplateMatchResult({
    required this.matches,
    required this.score,
    required this.matchedBubbles,
    required this.totalBubbles,
    required this.meanRingCoverage,
    required this.note,
  });

  final bool matches;
  final double score;
  final int matchedBubbles;
  final int totalBubbles;
  final double meanRingCoverage;
  final String note;
}

/// Verifies that a registered/rectified image is actually the Bayaz OMR
/// template, rather than merely a page that happens to contain four dark
/// corner squares. The printed bubble outlines provide dozens of redundant
/// geometry checks after rectification.
abstract final class OmrTemplateVerifier {
  static const int _angleSamples = 36;
  static const int _radialSamples = 8;

  static OmrTemplateMatchResult verify(img.Image canonical, OmrLayout layout) {
    var matched = 0;
    var total = 0;
    var coverageSum = 0.0;

    for (var question = 1; question <= layout.questionCount; question++) {
      for (var option = 0; option < layout.options; option++) {
        final coverage = _ringCoverage(canonical, layout, question, option);
        coverageSum += coverage;
        total++;
        if (coverage >= .42) matched++;
      }
    }

    final matchedFraction = total == 0 ? 0.0 : matched / total;
    final meanCoverage = total == 0 ? 0.0 : coverageSum / total;
    final score = (matchedFraction * .75 + meanCoverage * .25)
        .clamp(0.0, 1.0)
        .toDouble();
    final matches = matchedFraction >= .60 && meanCoverage >= .36;
    final note = matches
        ? 'Bayaz bubble grid aligned: $matched/$total outlines matched'
        : 'bubble grid mismatch: only $matched/$total expected outlines aligned';

    return OmrTemplateMatchResult(
      matches: matches,
      score: score,
      matchedBubbles: matched,
      totalBubbles: total,
      meanRingCoverage: meanCoverage,
      note: note,
    );
  }

  static double _ringCoverage(
    img.Image canonical,
    OmrLayout layout,
    int questionNumber,
    int optionIndex,
  ) {
    final (u, v) = layout.bubbleNorm(questionNumber, optionIndex);
    final cx = u * (canonical.width - 1);
    final cy = v * (canonical.height - 1);
    final radius = layout.bubbleR / layout.boxW * canonical.width;
    var covered = 0;

    for (var angleIndex = 0; angleIndex < _angleSamples; angleIndex++) {
      final angle = 2 * math.pi * angleIndex / _angleSamples;
      final cosAngle = math.cos(angle);
      final sinAngle = math.sin(angle);
      var darkest = 0.0;
      for (var radialIndex = 0; radialIndex < _radialSamples; radialIndex++) {
        final t = _radialSamples == 1
            ? 0.0
            : radialIndex / (_radialSamples - 1);
        final sampleRadius = radius * (.72 + .56 * t);
        final x = (cx + cosAngle * sampleRadius).round();
        final y = (cy + sinAngle * sampleRadius).round();
        if (x < 0 || y < 0 || x >= canonical.width || y >= canonical.height) {
          continue;
        }
        final darkness =
            (255 - canonical.getPixel(x, y).luminance.toDouble()) / 255.0;
        if (darkness > darkest) darkest = darkness;
      }
      if (darkest >= .16) covered++;
    }

    return covered / _angleSamples;
  }
}
