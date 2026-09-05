import 'package:bayaz_ai/features/omr/omr_diagnostics.dart';
import 'package:bayaz_ai/features/omr/omr_rectifier.dart';
import 'package:bayaz_ai/features/omr/omr_template.dart';
import 'package:bayaz_ai/features/omr/projective_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'rectifier maps perspective bubble positions into canonical coordinates',
    () {
      final source = img.Image(width: 900, height: 1200);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      final points = const [
        OmrPoint(130, 110),
        OmrPoint(790, 175),
        OmrPoint(720, 1080),
        OmrPoint(185, 1010),
      ];
      final mapper = ProjectiveMapper.fromUnitSquare([
        for (final p in points) (p.x, p.y),
      ])!;
      final layout = OmrTemplate.layoutFor(10);
      final (u, v) = layout.bubbleNorm(6, 2);
      final (sourceX, sourceY) = mapper.map(u, v);
      img.fillCircle(
        source,
        x: sourceX.round(),
        y: sourceY.round(),
        radius: 18,
        color: img.ColorRgb8(0, 0, 0),
      );

      final canonical = OmrRectifier.rectify(
        source,
        points,
        layout,
        canonicalWidth: 820,
      );

      expect(canonical.width, 820);
      expect(canonical.height, closeTo(1160, 4));
      final expectedX = (u * (canonical.width - 1)).round();
      final expectedY = (v * (canonical.height - 1)).round();
      expect(canonical.getPixel(expectedX, expectedY).luminance, lessThan(40));
      expect(canonical.getPixel(20, 20).luminance, greaterThan(230));
    },
  );
}
