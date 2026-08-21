import 'package:image/image.dart' as img;

import '../generation/mcq_parser.dart';
import 'omr_template.dart';

/// Per-question grading outcome.
class OmrQuestion {
  const OmrQuestion({
    required this.number,
    required this.marked,
    required this.correct,
    required this.fill,
  });
  final int number;
  final String? marked; // 'A'..'D' or null (blank/ambiguous)
  final String? correct; // key answer
  final double fill; // darkness of the chosen bubble (0..1), for diagnostics
  bool get isRight => marked != null && marked == correct;
}

/// Result of grading one answer sheet against a test's key.
class OmrResult {
  const OmrResult({required this.questions, required this.fiducialsFound});
  final List<OmrQuestion> questions;
  final bool fiducialsFound;

  int get total => questions.length;
  int get correct => questions.where((q) => q.isRight).length;
  int get blank => questions.where((q) => q.marked == null).length;
}

/// Reads a photographed OMR sheet and scores it against the stored key — no SLM.
/// Pipeline: grayscale → locate the 4 corner fiducials → bilinear-map each bubble
/// (known [OmrTemplate] positions) into the photo → measure interior darkness →
/// the darkest option per row (clearly above the rest) is the mark. See ADR-007.
class OmrGrader {
  // A bubble interior darker than this (0..1) counts as "filled".
  static const double _fillThreshold = 0.35;
  // The winner must beat the runner-up by at least this margin (else ambiguous).
  static const double _marginThreshold = 0.12;

  static OmrResult grade(img.Image image, McqTest key) {
    final gray = img.grayscale(image);
    final w = gray.width, h = gray.height;

    final fids = _findFiducials(gray);
    final answers = {for (final q in key.questions) q.number: q.answer};

    final out = <OmrQuestion>[];
    for (final q in key.questions) {
      final fills = <double>[];
      for (var c = 0; c < OmrTemplate.options; c++) {
        final (u, v) = OmrTemplate.bubbleNorm(q.number, c);
        final (px, py) = _map(fids, u, v);
        fills.add(_sampleFill(gray, px, py, w, h));
      }
      out.add(_decide(q.number, fills, answers[q.number]));
    }
    return OmrResult(questions: out, fiducialsFound: fids != null);
  }

  static OmrQuestion _decide(int number, List<double> fills, String? correct) {
    var best = 0, second = -1;
    for (var c = 1; c < fills.length; c++) {
      if (fills[c] > fills[best]) {
        second = best;
        best = c;
      }
    }
    final secondFill = second >= 0
        ? fills[second]
        : (fills..sort()).length > 1
            ? fills[fills.length - 2]
            : 0.0;
    final bestFill = fills.reduce((a, b) => a > b ? a : b);
    final marked = (bestFill >= _fillThreshold &&
            bestFill - secondFill >= _marginThreshold)
        ? String.fromCharCode(65 + best)
        : null;
    return OmrQuestion(
        number: number, marked: marked, correct: correct, fill: bestFill);
  }

  /// The 4 fiducial centers in photo pixels (TL, TR, BR, BL), or null if not found.
  static List<(double, double)>? _findFiducials(img.Image gray) {
    final w = gray.width, h = gray.height;
    // Search a generous corner window for the spot with the highest local darkness
    // — the solid square beats thin print. The teacher photographs the answer box,
    // so the corner squares sit near the image corners (with some framing margin).
    // Window ~ a fiducial as it appears when the box roughly fills the frame.
    final win = ((OmrTemplate.fidSize / OmrTemplate.boxH) * h * 0.9).round().clamp(6, 80);
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
    return result;
  }

  /// Locate the solid fiducial square in a corner region: first find the darkest
  /// [win]×[win] box (the solid square beats thin print/bubbles), then return the
  /// dark-pixel **centroid** inside it — precise regardless of where the square sat
  /// within the sliding window.
  static (double, double)? _darkestWindow(
      img.Image g, int x0, int y0, int x1, int y1, int win) {
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
    // Centroid of dark pixels within the winning window (± a small pad).
    const pad = 4;
    double sx = 0, sy = 0, wsum = 0;
    for (var y = (by - pad).clamp(0, g.height - 1);
        y < (by + win + pad).clamp(0, g.height);
        y++) {
      for (var x = (bx - pad).clamp(0, g.width - 1);
          x < (bx + win + pad).clamp(0, g.width);
          x++) {
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

  /// Bilinear map of a normalized point (u,v) into photo pixels via the 4 fiducials.
  static (double, double) _map(List<(double, double)>? fids, double u, double v) {
    if (fids == null) return (0, 0);
    final (tlx, tly) = fids[0];
    final (trx, tryy) = fids[1];
    final (brx, bry) = fids[2];
    final (blx, bly) = fids[3];
    final topX = tlx + (trx - tlx) * u, topY = tly + (tryy - tly) * u;
    final botX = blx + (brx - blx) * u, botY = bly + (bry - bly) * u;
    return (topX + (botX - topX) * v, topY + (botY - topY) * v);
  }

  /// Average darkness (0..1) inside a small disc at (px,py) — the bubble interior.
  static double _sampleFill(img.Image g, double px, double py, int w, int h) {
    // Sample radius slightly under the printed bubble radius to skip the outline.
    // Scale to the box (the framed region), not the whole page.
    final r = ((OmrTemplate.bubbleR * 0.7 / OmrTemplate.boxH) * h).round().clamp(2, 40);
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
