/// Shared OMR geometry, in A4 **points** with a top-left origin. The PDF export
/// draws the fiducials and answer bubbles at these exact coordinates, and the
/// grader samples the photographed sheet at the same (fiducial-normalized)
/// positions — so the two stay in lockstep. Framework-agnostic (plain doubles) so
/// it can be unit-tested without Flutter.
class OmrTemplate {
  const OmrTemplate._();

  // A4 page size in PDF points.
  static const double pageW = 595.28;
  static const double pageH = 841.89;

  static const int options = 4; // A B C D

  // --- Fiducial markers: filled squares near the 4 corners. ---
  static const double fidMargin = 12; // gap from the page edge to the square
  static const double fidSize = 14; // square side
  static double get _fidC => fidMargin + fidSize / 2; // center offset from edge

  /// Fiducial centers, order TL, TR, BR, BL (clockwise).
  static List<(double, double)> get fiducials => [
        (_fidC, _fidC),
        (pageW - _fidC, _fidC),
        (pageW - _fidC, pageH - _fidC),
        (_fidC, pageH - _fidC),
      ];

  // --- Answer grid (boxed, top-right). ---
  static const double boxLeft = 398;
  static const double boxTop = 40;
  static const double boxW = 167;
  static const double boxH = 232;

  static const double colA = 448; // x-center of column A bubbles
  static const double colPitch = 30; // A->B->C->D spacing
  static const double qLabelX = 406; // x of "Q#" labels
  static const double colLabelY = 74; // y of the A/B/C/D header row
  static const double row1 = 90; // y-center of Q1 bubbles
  static const double rowPitch = 17; // Q1->Q2 spacing
  static const double bubbleR = 6; // bubble radius

  /// x-center of option [c] (0=A..3=D).
  static double colX(int c) => colA + c * colPitch;

  /// y-center of question [q] (1-based).
  static double rowY(int q) => row1 + (q - 1) * rowPitch;

  /// Bubble center for question [q] (1-based), option [c] (0..3), in page points.
  static (double, double) bubbleCenter(int q, int c) => (colX(c), rowY(q));

  // --- Fiducial-normalized coordinates (for the grader). ---
  // The grader locates the 4 fiducial centers in the photo, then maps any page
  // point to the photo via bilinear blend using these normalized coords.
  static double get _left => _fidC;
  static double get _top => _fidC;
  static double get _spanX => pageW - 2 * _fidC;
  static double get _spanY => pageH - 2 * _fidC;

  /// Normalize a page point to [0,1] within the fiducial rectangle.
  static (double, double) norm(double x, double y) =>
      ((x - _left) / _spanX, (y - _top) / _spanY);

  /// Normalized bubble center for [q],[c] — what the grader samples.
  static (double, double) bubbleNorm(int q, int c) {
    final (x, y) = bubbleCenter(q, c);
    return norm(x, y);
  }
}
