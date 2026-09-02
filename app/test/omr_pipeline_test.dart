import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/omr/omr_diagnostics.dart';
import 'package:bayaz_ai/features/omr/omr_pipeline.dart';
import 'package:bayaz_ai/features/omr/omr_template.dart';
import 'package:bayaz_ai/features/omr/projective_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

McqTest _key({int count = 10}) => McqTest(
  topic: 'Cells',
  expectedCount: count,
  questions: [
    for (var i = 1; i <= count; i++)
      McqQuestion(
        number: i,
        difficulty: 'easy',
        text: 'Q$i',
        options: const {'A': 'a', 'B': 'b', 'C': 'c', 'D': 'd'},
        answer: 'ABCD'[(i - 1) % 4],
      ),
  ],
);

img.Image _renderSheet({
  int count = 10,
  Set<int> blank = const {},
  Map<int, Set<String>> extraMarks = const {},
  Set<int> shadowRows = const {},
}) {
  final layout = OmrTemplate.layoutFor(count);
  const scale = 4.0;
  const pad = 18.0;
  final originX = layout.boxLeft - pad;
  final originY = layout.boxTop - pad;
  final width = ((layout.boxW + 2 * pad) * scale).round();
  final height = ((layout.boxH + 2 * pad) * scale).round();
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(246, 246, 246));
  int sx(double x) => ((x - originX) * scale).round();
  int sy(double y) => ((y - originY) * scale).round();
  final markerHalf = (layout.fidSize * scale / 2).round();
  for (final (x, y) in layout.fiducials) {
    img.fillRect(
      image,
      x1: sx(x) - markerHalf,
      y1: sy(y) - markerHalf,
      x2: sx(x) + markerHalf,
      y2: sy(y) + markerHalf,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  final radius = (layout.bubbleR * scale).round();
  for (var q = 1; q <= count; q++) {
    if (shadowRows.contains(q)) {
      final y = sy(layout.rowY(q));
      img.fillRect(
        image,
        x1: sx(layout.boxLeft + 18),
        y1: y - radius * 2,
        x2: sx(layout.boxRight - 10),
        y2: y + radius * 2,
        color: img.ColorRgb8(155, 155, 155),
      );
    }
    final correct = 'ABCD'[(q - 1) % 4];
    for (var c = 0; c < 4; c++) {
      final option = 'ABCD'[c];
      final (x, y) = layout.bubbleCenter(q, c);
      img.drawCircle(
        image,
        x: sx(x),
        y: sy(y),
        radius: radius,
        color: img.ColorRgb8(15, 15, 15),
      );
      final selected = !blank.contains(q) && correct == option;
      final extra = extraMarks[q]?.contains(option) ?? false;
      if (selected || extra) {
        img.fillCircle(
          image,
          x: sx(x),
          y: sy(y),
          radius: radius - 2,
          color: img.ColorRgb8(20, 20, 20),
        );
      }
    }
  }
  return image;
}

img.Image _renderPerspectiveSheet() {
  final layout = OmrTemplate.layoutFor(10);
  final image = img.Image(width: 900, height: 1200);
  img.fill(image, color: img.ColorRgb8(242, 242, 242));
  final corners = <(double, double)>[
    (130, 100),
    (790, 175),
    (720, 1085),
    (190, 1015),
  ];
  final mapper = ProjectiveMapper.fromUnitSquare(corners)!;
  for (final (x, y) in corners) {
    img.fillRect(
      image,
      x1: x.round() - 24,
      y1: y.round() - 24,
      x2: x.round() + 24,
      y2: y.round() + 24,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  for (var q = 1; q <= 10; q++) {
    for (var c = 0; c < 4; c++) {
      final (u, v) = layout.bubbleNorm(q, c);
      final (x, y) = mapper.map(u, v);
      img.drawCircle(
        image,
        x: x.round(),
        y: y.round(),
        radius: 23,
        color: img.ColorRgb8(15, 15, 15),
      );
      if ('ABCD'[c] == 'ABCD'[(q - 1) % 4]) {
        img.fillCircle(
          image,
          x: x.round(),
          y: y.round(),
          radius: 21,
          color: img.ColorRgb8(20, 20, 20),
        );
      }
    }
  }
  return image;
}

void main() {
  test('pipeline grades a clean sheet and records stage diagnostics', () {
    final result = OmrPipeline.scan(_renderSheet(), _key());

    expect(result.fiducialsFound, isTrue);
    expect(result.correct, 10);
    expect(result.needsReview, 0);
    expect(result.diagnostics, isNotNull);
    expect(result.diagnostics!.status, OmrScanStatus.complete);
    expect(result.diagnostics!.rows, hasLength(10));
    expect(result.diagnostics!.markThreshold, inInclusiveRange(.10, .32));
    expect(
      result.diagnostics!.stageTimingsMs.keys,
      containsAll(['quality', 'registration', 'rectification', 'analysis']),
    );
  });

  test(
    'pipeline survives perspective distortion after canonical rectification',
    () {
      final result = OmrPipeline.scan(_renderPerspectiveSheet(), _key());

      expect(result.fiducialsFound, isTrue);
      expect(result.correct, 10);
      expect(result.diagnostics!.registrationScore, greaterThan(.45));
    },
  );

  test('pipeline uses local contrast under an uneven dark band', () {
    final result = OmrPipeline.scan(
      _renderSheet(shadowRows: const {4, 5, 6}),
      _key(),
    );

    expect(result.fiducialsFound, isTrue);
    expect(result.correct, 10);
  });

  test('pipeline sends blank and double-mark rows to teacher review', () {
    final result = OmrPipeline.scan(
      _renderSheet(
        blank: const {7},
        extraMarks: const {
          3: {'A'},
        },
      ),
      _key(),
    );

    expect(result.questions[2].decision, OmrDecisionKind.ambiguous);
    expect(result.questions[2].marked, isNull);
    expect(result.questions[6].decision, OmrDecisionKind.blank);
    expect(result.needsReview, 2);
  });

  test(
    'registration failure returns actionable diagnostics instead of guessing',
    () {
      final image = img.Image(width: 900, height: 1200);
      img.fill(image, color: img.ColorRgb8(245, 245, 245));

      final result = OmrPipeline.scan(image, _key());

      expect(result.fiducialsFound, isFalse);
      expect(result.correct, 0);
      expect(result.diagnostics!.status, OmrScanStatus.rejected);
      expect(result.diagnostics!.failureCode, OmrFailureCode.fiducialsNotFound);
      expect(result.diagnostics!.registrationNote, isNotEmpty);
      expect(
        result.diagnostics!.toReport(),
        contains('failure=fiducialsNotFound'),
      );
    },
  );
}
