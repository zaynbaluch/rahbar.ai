import 'package:bayaz_ai/features/omr/omr_diagnostics.dart';
import 'package:bayaz_ai/features/omr/omr_image_quality.dart';
import 'package:bayaz_ai/features/omr/omr_registration.dart';
import 'package:bayaz_ai/features/omr/omr_template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _markerImage({
  int width = 900,
  int height = 1200,
  List<(int, int)>? centers,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(238, 238, 238));
  final black = img.ColorRgb8(0, 0, 0);
  for (final (x, y)
      in centers ?? const [(110, 130), (785, 155), (760, 1060), (135, 1035)]) {
    img.fillRect(
      image,
      x1: x - 22,
      y1: y - 22,
      x2: x + 22,
      y2: y + 22,
      color: black,
    );
  }
  return image;
}

void main() {
  test('quality metrics identify usable dimensions and exposure', () {
    final image = _markerImage();
    final quality = OmrImageQuality.measure(img.grayscale(image));

    expect(quality.usableDimensions, isTrue);
    expect(quality.meanLuminance, greaterThan(200));
    expect(quality.darkClipFraction, greaterThan(0));
    expect(quality.lightClipFraction, lessThan(1));
    expect(quality.blurVariance, greaterThanOrEqualTo(0));
  });

  test('registration finds four solid square markers under perspective', () {
    final image = _markerImage();
    final result = OmrRegistration.detect(
      img.grayscale(image),
      OmrTemplate.layoutFor(10),
    );

    expect(result.success, isTrue);
    expect(result.failureCode, OmrFailureCode.none);
    expect(result.candidateCount, greaterThanOrEqualTo(4));
    expect(result.fiducials, hasLength(4));
    expect(result.fiducials[0].x, closeTo(110, 8));
    expect(result.fiducials[0].y, closeTo(130, 8));
    expect(result.fiducials[2].x, closeTo(760, 8));
    expect(result.score, greaterThan(.5));
  });

  test('registration rejects large dark corner clutter as fiducials', () {
    final image = img.Image(width: 900, height: 1200);
    img.fill(image, color: img.ColorRgb8(245, 245, 245));
    final black = img.ColorRgb8(0, 0, 0);
    img.fillRect(image, x1: 0, y1: 0, x2: 300, y2: 300, color: black);
    img.fillRect(image, x1: 600, y1: 0, x2: 899, y2: 300, color: black);
    img.fillRect(image, x1: 600, y1: 900, x2: 899, y2: 1199, color: black);
    img.fillRect(image, x1: 0, y1: 900, x2: 300, y2: 1199, color: black);

    final result = OmrRegistration.detect(
      img.grayscale(image),
      OmrTemplate.layoutFor(10),
    );

    expect(result.success, isFalse);
    expect(result.failureCode, OmrFailureCode.fiducialsNotFound);
  });

  test('registration rejects an unusably tiny image with a typed reason', () {
    final image = img.Image(width: 120, height: 180);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    final result = OmrRegistration.detect(image, OmrTemplate.layoutFor(10));

    expect(result.success, isFalse);
    expect(result.failureCode, OmrFailureCode.imageTooSmall);
  });
}
