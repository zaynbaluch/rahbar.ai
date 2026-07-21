/// Maps normalized sheet coordinates into a photographed quadrilateral.
///
/// A phone camera produces a projective transform, so interior points must use
/// the same homography defined by the four detected corner markers.
class ProjectiveMapper {
  const ProjectiveMapper._(
    this._a,
    this._b,
    this._c,
    this._d,
    this._e,
    this._f,
    this._g,
    this._h,
  );

  final double _a;
  final double _b;
  final double _c;
  final double _d;
  final double _e;
  final double _f;
  final double _g;
  final double _h;

  /// Builds the homography from unit-square corners ordered TL, TR, BR, BL.
  static ProjectiveMapper? fromUnitSquare(
    List<(double, double)> corners,
  ) {
    if (corners.length != 4) return null;
    final (tlx, tly) = corners[0];
    final (trx, tryy) = corners[1];
    final (brx, bry) = corners[2];
    final (blx, bly) = corners[3];

    final dx1 = trx - brx;
    final dx2 = blx - brx;
    final dx3 = tlx - trx + brx - blx;
    final dy1 = tryy - bry;
    final dy2 = bly - bry;
    final dy3 = tly - tryy + bry - bly;

    double g;
    double h;
    const epsilon = 1e-9;
    if (dx3.abs() < epsilon && dy3.abs() < epsilon) {
      g = 0;
      h = 0;
    } else {
      final denominator = dx1 * dy2 - dx2 * dy1;
      if (denominator.abs() < epsilon) return null;
      g = (dx3 * dy2 - dx2 * dy3) / denominator;
      h = (dx1 * dy3 - dx3 * dy1) / denominator;
    }

    return ProjectiveMapper._(
      trx - tlx + g * trx,
      blx - tlx + h * blx,
      tlx,
      tryy - tly + g * tryy,
      bly - tly + h * bly,
      tly,
      g,
      h,
    );
  }

  (double, double) map(double u, double v) {
    final scale = _g * u + _h * v + 1;
    return (
      (_a * u + _b * v + _c) / scale,
      (_d * u + _e * v + _f) / scale,
    );
  }
}
