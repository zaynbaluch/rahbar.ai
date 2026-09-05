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

  test(
    'registration isolates fiducials even when the printed box border touches them',
    () {
      final image = _markerImage();
      final black = img.ColorRgb8(0, 0, 0);
      // Mirror the shipping PDF: the answer-box border runs through each marker center.
      img.drawLine(
        image,
        x1: 110,
        y1: 130,
        x2: 785,
        y2: 155,
        color: black,
        thickness: 3,
      );
      img.drawLine(
        image,
        x1: 785,
        y1: 155,
        x2: 760,
        y2: 1060,
        color: black,
        thickness: 3,
      );
      img.drawLine(
        image,
        x1: 760,
        y1: 1060,
        x2: 135,
        y2: 1035,
        color: black,
        thickness: 3,
      );
      img.drawLine(
        image,
        x1: 135,
        y1: 1035,
        x2: 110,
        y2: 130,
        color: black,
        thickness: 3,
      );

      final result = OmrRegistration.detect(
        img.grayscale(image),
        OmrTemplate.layoutFor(10),
      );

      expect(result.success, isTrue);
      expect(result.fiducials, hasLength(4));
      expect(result.fiducials[0].x, closeTo(110, 10));
      expect(result.fiducials[2].y, closeTo(1060, 10));
    },
  );

  test(
    'registration search stays explicitly bounded under heavy square clutter',
    () {
      final image = img.Image(width: 900, height: 1200);
      img.fill(image, color: img.ColorRgb8(242, 242, 242));
      final black = img.ColorRgb8(0, 0, 0);
      for (var row = 0; row < 9; row++) {
        for (var col = 0; col < 8; col++) {
          final x = 45 + col * 105;
          final y = 55 + row * 120;
          img.fillRect(
            image,
            x1: x - 10,
            y1: y - 10,
            x2: x + 10,
            y2: y + 10,
            color: black,
          );
        }
      }

      final result = OmrRegistration.detect(
        img.grayscale(image),
        OmrTemplate.layoutFor(10),
      );

      expect(result.candidateCount, greaterThan(48));
      expect(
        result.retainedCandidateCount,
        lessThanOrEqualTo(OmrRegistration.maxRetainedCandidates),
      );
      expect(
        result.hypotheses.length,
        lessThanOrEqualTo(OmrRegistration.maxHypotheses),
      );
      expect(
        result.combinationsEvaluated,
        lessThanOrEqualTo(
          OmrRegistration.maxRetainedCandidates *
              OmrRegistration.maxDirectionalPartners *
              OmrRegistration.maxDirectionalPartners *
              OmrRegistration.maxBottomRightPartners,
        ),
      );
    },
  );
}
