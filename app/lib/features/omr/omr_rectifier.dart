import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'omr_diagnostics.dart';
import 'omr_template.dart';
import 'projective_mapper.dart';

abstract final class OmrRectifier {
  static img.Image rectify(
    img.Image gray,
    List<OmrPoint> fiducials,
    OmrLayout layout, {
    int canonicalWidth = 820,
  }) {
    if (fiducials.length != 4) {
      throw ArgumentError.value(
        fiducials.length,
        'fiducials',
        'Four fiducial centers are required.',
      );
    }
    if (canonicalWidth < 64) {
      throw ArgumentError.value(
        canonicalWidth,
        'canonicalWidth',
        'Canonical width must be at least 64 pixels.',
      );
    }
    final mapper = ProjectiveMapper.fromUnitSquare([
      for (final point in fiducials) (point.x, point.y),
    ]);
    if (mapper == null) {
      throw ArgumentError('Fiducials do not define a usable homography.');
    }

    final canonicalHeight = (canonicalWidth * layout.boxH / layout.boxW)
        .round();
    final output = img.Image(width: canonicalWidth, height: canonicalHeight);
    for (var y = 0; y < canonicalHeight; y++) {
      final v = canonicalHeight == 1 ? 0.0 : y / (canonicalHeight - 1);
      for (var x = 0; x < canonicalWidth; x++) {
        final u = canonicalWidth == 1 ? 0.0 : x / (canonicalWidth - 1);
        final (sourceX, sourceY) = mapper.map(u, v);
        final value = _bilinearLuminance(gray, sourceX, sourceY);
        output.setPixelRgb(x, y, value, value, value);
      }
    }
    return output;
  }

  static int _bilinearLuminance(img.Image image, double x, double y) {
    final clampedX = x.clamp(0.0, (image.width - 1).toDouble());
    final clampedY = y.clamp(0.0, (image.height - 1).toDouble());
    final x0 = clampedX.floor();
    final y0 = clampedY.floor();
    final x1 = math.min(x0 + 1, image.width - 1);
    final y1 = math.min(y0 + 1, image.height - 1);
    final fx = clampedX - x0;
    final fy = clampedY - y0;
    final topLeft = image.getPixel(x0, y0).luminance.toDouble();
    final topRight = image.getPixel(x1, y0).luminance.toDouble();
    final bottomLeft = image.getPixel(x0, y1).luminance.toDouble();
    final bottomRight = image.getPixel(x1, y1).luminance.toDouble();
    final top = topLeft + (topRight - topLeft) * fx;
    final bottom = bottomLeft + (bottomRight - bottomLeft) * fx;
    return (top + (bottom - top) * fy).round().clamp(0, 255);
  }
}
