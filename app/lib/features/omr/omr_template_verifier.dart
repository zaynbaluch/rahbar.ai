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
    required this.borderCoverage,
    required this.minimumSideBorderCoverage,
    required this.note,
  });

  final bool matches;
  final double score;
  final int matchedBubbles;
  final int totalBubbles;
  final double meanRingCoverage;
  final double borderCoverage;
  final double minimumSideBorderCoverage;
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
    final sideBorders = _borderCoverages(canonical);
    final borderCoverage =
        sideBorders.reduce((a, b) => a + b) / sideBorders.length;
    final minimumSideBorderCoverage = sideBorders.reduce(math.min);
    final score =
        (matchedFraction * .55 + meanCoverage * .20 + borderCoverage * .25)
            .clamp(0.0, 1.0)
            .toDouble();
    final bubbleGridMatches = matchedFraction >= .60 && meanCoverage >= .36;
    final borderMatches =
        borderCoverage >= .58 && minimumSideBorderCoverage >= .38;
    final matches = bubbleGridMatches && borderMatches;
    final note = matches
        ? 'Bayaz template aligned: $matched/$total outlines matched; border ${(borderCoverage * 100).round()}%'
        : !borderMatches
        ? 'answer-box border mismatch: average ${(borderCoverage * 100).round()}%, weakest side ${(minimumSideBorderCoverage * 100).round()}%'
        : 'bubble grid mismatch: only $matched/$total expected outlines aligned';

    return OmrTemplateMatchResult(
      matches: matches,
      score: score,
      matchedBubbles: matched,
      totalBubbles: total,
      meanRingCoverage: meanCoverage,
      borderCoverage: borderCoverage,
      minimumSideBorderCoverage: minimumSideBorderCoverage,
      note: note,
    );
  }

  static List<double> _borderCoverages(img.Image canonical) {
    const samples = 96;
    final band = math.max(
      3,
      (math.min(canonical.width, canonical.height) * .007).round(),
    );

    double horizontal(bool top) {
      var covered = 0;
      for (var i = 0; i < samples; i++) {
        final t = .09 + .82 * i / (samples - 1);
        final x = (t * (canonical.width - 1)).round();
        var darkest = 0.0;
        for (var offset = 0; offset <= band; offset++) {
          final y = top ? offset : canonical.height - 1 - offset;
          final darkness =
              (255 - canonical.getPixel(x, y).luminance.toDouble()) / 255.0;
          if (darkness > darkest) darkest = darkness;
        }
        if (darkest >= .14) covered++;
      }
      return covered / samples;
    }

    double vertical(bool left) {
      var covered = 0;
      for (var i = 0; i < samples; i++) {
        final t = .09 + .82 * i / (samples - 1);
        final y = (t * (canonical.height - 1)).round();
        var darkest = 0.0;
        for (var offset = 0; offset <= band; offset++) {
          final x = left ? offset : canonical.width - 1 - offset;
          final darkness =
              (255 - canonical.getPixel(x, y).luminance.toDouble()) / 255.0;
          if (darkness > darkest) darkest = darkness;
        }
        if (darkest >= .14) covered++;
      }
      return covered / samples;
    }

    return [
      horizontal(true),
      vertical(false),
      horizontal(false),
      vertical(true),
    ];
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
