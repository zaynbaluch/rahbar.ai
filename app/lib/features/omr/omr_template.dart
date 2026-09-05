/// OMR geometry in A4 PDF points, with a top-left origin.
///
/// Ten-question papers keep the original coordinates exactly. Fifteen-question
/// papers use the same columns/pitch and simply extend the registration box far
/// enough to contain rows 11-15.
class OmrLayout {
  const OmrLayout({required this.questionCount, required this.boxH});

  final int questionCount;
  final double boxH;

  double get pageW => 595.28;
  double get pageH => 841.89;
  int get options => 4;
  double get boxLeft => 400;
  double get boxTop => 44;
  double get boxW => 164;
  double get fidSize => 12;
  double get colA => 440;
  double get colPitch => 30;
  double get qLabelX => 409;
  double get colLabelY => 62;
  double get row1 => 78;
  double get rowPitch => 16.5;
  double get bubbleR => 6;

  double get boxRight => boxLeft + boxW;
  double get boxBottom => boxTop + boxH;

  List<(double, double)> get fiducials => [
    (boxLeft, boxTop),
    (boxRight, boxTop),
    (boxRight, boxBottom),
    (boxLeft, boxBottom),
  ];

  double colX(int c) => colA + c * colPitch;
  double rowY(int q) => row1 + (q - 1) * rowPitch;
  (double, double) bubbleCenter(int q, int c) => (colX(c), rowY(q));

  double get _spanX => boxRight - boxLeft;
  double get _spanY => boxBottom - boxTop;
  (double, double) norm(double x, double y) =>
      ((x - boxLeft) / _spanX, (y - boxTop) / _spanY);
  (double, double) bubbleNorm(int q, int c) {
    final (x, y) = bubbleCenter(q, c);
    return norm(x, y);
  }
}

abstract final class OmrTemplate {
  static const double pageW = 595.28;
  static const double pageH = 841.89;
  static const int options = 4;
  static const double boxLeft = 400;
  static const double boxTop = 44;
  static const double boxW = 164;
  static const double boxH = 232;
  static const double fidSize = 12;
  static const double colA = 440;
  static const double colPitch = 30;
  static const double qLabelX = 409;
  static const double colLabelY = 62;
  static const double row1 = 78;
  static const double rowPitch = 16.5;
  static const double bubbleR = 6;

  static OmrLayout layoutFor(int questionCount) {
    if (questionCount <= 0 || questionCount > 15) {
      throw ArgumentError.value(
        questionCount,
        'questionCount',
        'OMR supports between 1 and 15 questions.',
      );
    }
    return OmrLayout(
      questionCount: questionCount,
      boxH: questionCount <= 10 ? boxH : 288,
    );
  }

  // Legacy 10-question accessors remain so every existing OMR test and caller
  // continues to exercise the exact shipping geometry.
  static OmrLayout get _legacy => layoutFor(10);
  static double get boxRight => _legacy.boxRight;
  static double get boxBottom => _legacy.boxBottom;
  static List<(double, double)> get fiducials => _legacy.fiducials;
  static double colX(int c) => _legacy.colX(c);
  static double rowY(int q) => _legacy.rowY(q);
  static (double, double) bubbleCenter(int q, int c) =>
      _legacy.bubbleCenter(q, c);
  static (double, double) norm(double x, double y) => _legacy.norm(x, y);
  static (double, double) bubbleNorm(int q, int c) => _legacy.bubbleNorm(q, c);
}
