import 'package:bayaz_ai/features/omr/omr_bubble_analysis.dart';
import 'package:bayaz_ai/features/omr/omr_diagnostics.dart';
import 'package:bayaz_ai/features/omr/omr_template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _canonical({
  int questionCount = 10,
  Map<int, String> marks = const {},
  Map<int, int> rowBackground = const {},
  Map<int, Map<String, int>> customFill = const {},
}) {
  final layout = OmrTemplate.layoutFor(questionCount);
  const width = 820;
  final height = (width * layout.boxH / layout.boxW).round();
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final bubbleRadius = (layout.bubbleR / layout.boxW * width).round();
  for (var q = 1; q <= questionCount; q++) {
    final (_, v) = layout.bubbleNorm(q, 0);
    final cy = (v * (height - 1)).round();
    final background = rowBackground[q];
    if (background != null) {
      img.fillRect(
        image,
        x1: 0,
        y1: (cy - bubbleRadius * 2).clamp(0, height - 1),
        x2: width - 1,
        y2: (cy + bubbleRadius * 2).clamp(0, height - 1),
        color: img.ColorRgb8(background, background, background),
      );
    }
    for (var c = 0; c < 4; c++) {
      final option = 'ABCD'[c];
      final (u, vv) = layout.bubbleNorm(q, c);
      final cx = (u * (width - 1)).round();
      final y = (vv * (height - 1)).round();
      img.drawCircle(
        image,
        x: cx,
        y: y,
        radius: bubbleRadius,
        color: img.ColorRgb8(20, 20, 20),
      );
      final custom = customFill[q]?[option];
      if (marks[q] == option || custom != null) {
        final value = custom ?? 20;
        img.fillCircle(
          image,
          x: cx,
          y: y,
          radius: bubbleRadius - 3,
          color: img.ColorRgb8(value, value, value),
        );
      }
    }
  }
  return image;
}

void main() {
  test('sampler separates a clean filled bubble from an empty bubble', () {
    final layout = OmrTemplate.layoutFor(10);
    final image = _canonical(marks: const {1: 'B'});

    final empty = OmrBubbleSampler.sample(image, layout, 1, 0);
    final filled = OmrBubbleSampler.sample(image, layout, 1, 1);

    expect(empty.score, lessThan(.08));
    expect(filled.score, greaterThan(.55));
    expect(filled.localContrast, greaterThan(.5));
    expect(filled.darkPixelDensity, greaterThan(.7));
  });

  test('local background comparison resists a dark lighting band', () {
    final layout = OmrTemplate.layoutFor(10);
    final image = _canonical(
      marks: const {4: 'C'},
      rowBackground: const {4: 155},
    );

    final blank = OmrBubbleSampler.sample(image, layout, 4, 0);
    final filled = OmrBubbleSampler.sample(image, layout, 4, 2);

    expect(blank.score, lessThan(.10));
    expect(filled.score, greaterThan(.45));
  });

  test(
    'calibration learns the blank population rather than absolute brightness',
    () {
      final layout = OmrTemplate.layoutFor(10);
      final image = _canonical(
        marks: {for (var q = 1; q <= 10; q++) q: 'ABCD'[(q - 1) % 4]},
      );
      final observations = <OmrBubbleDiagnostic>[
        for (var q = 1; q <= 10; q++)
          for (var c = 0; c < 4; c++)
            OmrBubbleSampler.sample(image, layout, q, c),
      ];

      final calibration = OmrSheetCalibration.fromObservations(observations);

      expect(calibration.blankBaseline, lessThan(.08));
      expect(calibration.markThreshold, inInclusiveRange(.10, .32));
      final filledScores = [
        for (var q = 1; q <= 10; q++)
          observations[(q - 1) * 4 + ((q - 1) % 4)].score,
      ];
      expect(
        filledScores.every((score) => score > calibration.markThreshold),
        isTrue,
      );
    },
  );

  test('classifier returns ambiguous when two bubbles are clearly marked', () {
    final layout = OmrTemplate.layoutFor(10);
    final image = _canonical(
      marks: const {1: 'A'},
      customFill: const {
        1: {'B': 25},
      },
    );
    final bubbles = [
      for (var c = 0; c < 4; c++) OmrBubbleSampler.sample(image, layout, 1, c),
    ];
    final calibration = OmrSheetCalibration.fromObservations([
      ...bubbles,
      for (var q = 2; q <= 10; q++)
        for (var c = 0; c < 4; c++)
          OmrBubbleSampler.sample(_canonical(), layout, q, c),
    ]);

    final decision = OmrRowClassifier.classify(bubbles, calibration);

    expect(decision.decision, OmrDecisionKind.ambiguous);
    expect(decision.marked, isNull);
    expect(decision.reason, contains('multiple'));
  });

  test(
    'faint winner is retained but carries low confidence for teacher review',
    () {
      final layout = OmrTemplate.layoutFor(10);
      final image = _canonical(
        customFill: const {
          1: {'C': 210},
        },
      );
      final bubbles = [
        for (var c = 0; c < 4; c++)
          OmrBubbleSampler.sample(image, layout, 1, c),
      ];
      const calibration = OmrSheetCalibration(
        blankBaseline: .01,
        blankMad: .005,
        markThreshold: .10,
      );

      final decision = OmrRowClassifier.classify(bubbles, calibration);

      expect(decision.decision, OmrDecisionKind.marked);
      expect(decision.marked, 'C');
      expect(decision.confidence, lessThan(.20));
    },
  );
}
