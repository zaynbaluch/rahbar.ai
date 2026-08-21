/// Shared OMR geometry, in A4 **points** with a top-left origin. The PDF export
/// draws the fiducials and answer bubbles at these exact coordinates, and the
/// grader samples the photographed sheet at the same (fiducial-normalized)
/// positions — so the two stay in lockstep. Framework-agnostic (plain doubles) so
/// it can be unit-tested without Flutter.
///
/// The four fiducial squares sit at the corners of the **answer box** (not the page
/// corners), so the teacher can photograph just the box — far more pixels per
/// bubble than a whole-sheet shot, and easier to frame.
class OmrTemplate {
  const OmrTemplate._();

  // A4 page size in PDF points (for the PDF page + absolute drawing).
  static const double pageW = 595.28;
  static const double pageH = 841.89;

  static const int options = 4; // A B C D

  // --- Answer box (boxed, top-right of the sheet). ---
  static const double boxLeft = 400;
  static const double boxTop = 44;
  static const double boxW = 164;
  static const double boxH = 232;
  static double get boxRight => boxLeft + boxW;
  static double get boxBottom => boxTop + boxH;

  // --- Fiducial markers: solid squares centered on the four box corners. They
  // form the registration rectangle the grader locks onto. ---
  static const double fidSize = 12;

  /// Fiducial centers, order TL, TR, BR, BL (clockwise).
  static List<(double, double)> get fiducials => [
        (boxLeft, boxTop),
        (boxRight, boxTop),
        (boxRight, boxBottom),
        (boxLeft, boxBottom),
      ];

  // --- Bubble grid (inside the box). ---
  static const double colA = 440; // x-center of column A bubbles
  static const double colPitch = 30; // A->B->C->D spacing
  static const double qLabelX = 409; // x of "Q#" labels
  static const double colLabelY = 62; // y of the A/B/C/D header row
  static const double row1 = 78; // y-center of Q1 bubbles
  static const double rowPitch = 16.5; // Q1->Q2 spacing
  static const double bubbleR = 6; // bubble radius

  /// x-center of option [c] (0=A..3=D).
  static double colX(int c) => colA + c * colPitch;

  /// y-center of question [q] (1-based).
  static double rowY(int q) => row1 + (q - 1) * rowPitch;

  /// Bubble center for question [q] (1-based), option [c] (0..3), in page points.
  static (double, double) bubbleCenter(int q, int c) => (colX(c), rowY(q));

  // --- Fiducial-normalized coordinates (for the grader). ---
  // The grader locates the 4 fiducial (box-corner) centers in the photo, then maps
  // any page point to the photo via bilinear blend using these normalized coords.
  static double get _spanX => boxRight - boxLeft;
  static double get _spanY => boxBottom - boxTop;

  /// Normalize a page point to [0,1] within the fiducial (box) rectangle.
  static (double, double) norm(double x, double y) =>
      ((x - boxLeft) / _spanX, (y - boxTop) / _spanY);

  /// Normalized bubble center for [q],[c] — what the grader samples.
  static (double, double) bubbleNorm(int q, int c) {
    final (x, y) = bubbleCenter(q, c);
    return norm(x, y);
  }
}
