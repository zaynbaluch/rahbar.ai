import 'package:image/image.dart' as img;

import '../generation/mcq_parser.dart';
import 'omr_diagnostics.dart';
import 'omr_template.dart';
import 'projective_mapper.dart';

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
  final String? marked; // 'A'..'D' or null (blank/ambiguous)
  final String? correct; // key answer
  final double fill; // darkness of the chosen bubble (0..1), for diagnostics
  final double confidence; // winner margin, 0..1
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
  int get correct => questions.where((q) => q.isRight).length;
  int get blank => questions.where((q) => q.marked == null).length;
  int get needsReview => questions
      .where(
        (q) =>
            !q.reviewed &&
            (q.decision != OmrDecisionKind.marked || q.confidence < 0.20),
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

/// Reads a photographed OMR sheet and scores it against the stored key — no SLM.
/// Pipeline: grayscale → locate the 4 corner fiducials → projectively map each bubble
/// (known [OmrTemplate] positions) into the photo → measure interior darkness →
/// the darkest option per row (clearly above the rest) is the mark. See ADR-007.
class OmrGrader {
  // A bubble interior darker than this (0..1) counts as "filled".
  static const double _fillThreshold = 0.35;
  // The winner must beat the runner-up by at least this margin (else ambiguous).
  static const double _marginThreshold = 0.12;

  static OmrResult grade(img.Image image, McqTest key) {
    final validation = key.validation;
    if (!validation.isReady) {
      throw StateError('Cannot grade an invalid paper: ${validation.summary}');
    }
    final gray = img.grayscale(image);
    final w = gray.width, h = gray.height;
    final layout = OmrTemplate.layoutFor(key.expectedCount);

    final fids = _findFiducials(gray, layout);
    final mapper = fids == null ? null : ProjectiveMapper.fromUnitSquare(fids);
    final answers = {for (final q in key.questions) q.number: q.answer};

    final out = <OmrQuestion>[];
    for (final q in key.questions) {
      final fills = <double>[];
      for (var c = 0; c < OmrTemplate.options; c++) {
        final (u, v) = layout.bubbleNorm(q.number, c);
        final (px, py) = mapper?.map(u, v) ?? (0.0, 0.0);
        fills.add(_sampleFill(gray, px, py, w, h, layout));
      }
      out.add(_decide(q.number, fills, answers[q.number]));
    }
    return OmrResult(questions: out, fiducialsFound: mapper != null);
  }

  static OmrQuestion _decide(int number, List<double> fills, String? correct) {
    final ranked = [
      for (var i = 0; i < fills.length; i++) (index: i, fill: fills[i]),
    ]..sort((a, b) => b.fill.compareTo(a.fill));
    final best = ranked.first;
    final secondFill = ranked.length > 1 ? ranked[1].fill : 0.0;
    final margin = (best.fill - secondFill).clamp(0.0, 1.0).toDouble();
    final marked = (best.fill >= _fillThreshold && margin >= _marginThreshold)
        ? String.fromCharCode(65 + best.index)
        : null;
    return OmrQuestion(
      number: number,
      marked: marked,
      correct: correct,
      fill: best.fill,
      confidence: margin,
    );
  }

  /// The 4 fiducial centers in photo pixels (TL, TR, BR, BL), or null if not found.
  static List<(double, double)>? _findFiducials(
    img.Image gray,
    OmrLayout layout,
  ) {
    final w = gray.width, h = gray.height;
    // Search a generous corner window for the spot with the highest local darkness
    // — the solid square beats thin print. The teacher photographs the answer box,
    // so the corner squares sit near the image corners (with some framing margin).
    // Window ~ a fiducial as it appears when the box roughly fills the frame.
    final win = ((layout.fidSize / layout.boxH) * h * 0.9).round().clamp(6, 80);
    final regionW = (w * 0.45).round(), regionH = (h * 0.45).round();
    final corners = <(int, int, int, int)>[
      (0, 0, regionW, regionH), // TL
      (w - regionW, 0, w, regionH), // TR
      (w - regionW, h - regionH, w, h), // BR
      (0, h - regionH, regionW, h), // BL
    ];
    final result = <(double, double)>[];
    for (final (x0, y0, x1, y1) in corners) {
      final spot = _darkestWindow(gray, x0, y0, x1, y1, win);
      if (spot == null) return null;
      result.add(spot);
    }
    if (!_validFiducialGeometry(result, w, h)) return null;
    return result;
  }

  static bool _validFiducialGeometry(
    List<(double, double)> points,
    int width,
    int height,
  ) {
    if (points.length != 4) return false;
    double distance((double, double) a, (double, double) b) {
      final dx = a.$1 - b.$1;
      final dy = a.$2 - b.$2;
      return (dx * dx + dy * dy);
    }

    final top2 = distance(points[0], points[1]);
    final right2 = distance(points[1], points[2]);
    final bottom2 = distance(points[3], points[2]);
    final left2 = distance(points[0], points[3]);
    final minHorizontal2 = width * width * 0.12;
    final minVertical2 = height * height * 0.12;
    if (top2 < minHorizontal2 ||
        bottom2 < minHorizontal2 ||
        left2 < minVertical2 ||
        right2 < minVertical2) {
      return false;
    }
    final horizontalRatio = top2 > bottom2 ? top2 / bottom2 : bottom2 / top2;
    final verticalRatio = left2 > right2 ? left2 / right2 : right2 / left2;
    if (horizontalRatio > 2.5 || verticalRatio > 2.5) return false;

    final tl = points[0], tr = points[1], br = points[2], bl = points[3];
    if (tl.$1 >= tr.$1 || bl.$1 >= br.$1 || tl.$2 >= bl.$2 || tr.$2 >= br.$2) {
      return false;
    }
    return true;
  }

  /// Locate the solid fiducial square in a corner region: first find the darkest
  /// [win]×[win] box (the solid square beats thin print/bubbles), then return the
  /// dark-pixel **centroid** inside it — precise regardless of where the square sat
  /// within the sliding window.
  static (double, double)? _darkestWindow(
    img.Image g,
    int x0,
    int y0,
    int x1,
    int y1,
    int win,
  ) {
    double bestDark = -1;
    int bx = -1, by = -1;
    final step = (win ~/ 4).clamp(2, 15);
    for (var y = y0; y + win <= y1; y += step) {
      for (var x = x0; x + win <= x1; x += step) {
        double sum = 0;
        for (var j = 0; j < win; j += 2) {
          for (var i = 0; i < win; i += 2) {
            sum += 255 - g.getPixel(x + i, y + j).luminance.toDouble();
          }
        }
        if (sum > bestDark) {
          bestDark = sum;
          bx = x;
          by = y;
        }
      }
    }
    if (bx < 0) return null;
    final samplesPerWindow = ((win + 1) ~/ 2) * ((win + 1) ~/ 2);
    final averageDarkness = bestDark / (samplesPerWindow * 255.0);
    if (averageDarkness < 0.42) return null;
    final ringPad = (win ~/ 2).clamp(4, 30);
    double ringDark = 0;
    int ringCount = 0;
    for (
      var y = (by - ringPad).clamp(y0, y1 - 1);
      y < (by + win + ringPad).clamp(y0 + 1, y1);
      y += 2
    ) {
      for (
        var x = (bx - ringPad).clamp(x0, x1 - 1);
        x < (bx + win + ringPad).clamp(x0 + 1, x1);
        x += 2
      ) {
        if (x >= bx && x < bx + win && y >= by && y < by + win) continue;
        ringDark += 255 - g.getPixel(x, y).luminance.toDouble();
        ringCount++;
      }
    }
    final ringAverage = ringCount == 0 ? 0.0 : ringDark / (ringCount * 255.0);
    if (ringAverage > 0.38 || averageDarkness - ringAverage < 0.22) return null;
    // Centroid of dark pixels within the winning window (± a small pad).
    const pad = 4;
    double sx = 0, sy = 0, wsum = 0;
    for (
      var y = (by - pad).clamp(0, g.height - 1);
      y < (by + win + pad).clamp(0, g.height);
      y++
    ) {
      for (
        var x = (bx - pad).clamp(0, g.width - 1);
        x < (bx + win + pad).clamp(0, g.width);
        x++
      ) {
        final dark = 255 - g.getPixel(x, y).luminance.toDouble();
        if (dark > 128) {
          sx += x * dark;
          sy += y * dark;
          wsum += dark;
        }
      }
    }
    if (wsum == 0) return (bx + win / 2, by + win / 2);
    return (sx / wsum, sy / wsum);
  }

  /// Average darkness (0..1) inside a small disc at (px,py) — the bubble interior.
  static double _sampleFill(
    img.Image g,
    double px,
    double py,
    int w,
    int h,
    OmrLayout layout,
  ) {
    // Sample radius slightly under the printed bubble radius to skip the outline.
    // Scale to the box (the framed region), not the whole page.
    final r = ((layout.bubbleR * 0.7 / layout.boxH) * h).round().clamp(2, 40);
    final cx = px.round(), cy = py.round();
    double sum = 0;
    int count = 0;
    for (var j = -r; j <= r; j++) {
      for (var i = -r; i <= r; i++) {
        if (i * i + j * j > r * r) continue;
        final x = cx + i, y = cy + j;
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        sum += 255 - g.getPixel(x, y).luminance;
        count++;
      }
    }
    return count == 0 ? 0 : (sum / count) / 255.0;
  }
}
