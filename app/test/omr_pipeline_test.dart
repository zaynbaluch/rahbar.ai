import 'dart:math' as math;

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
  final black = img.ColorRgb8(0, 0, 0);
  img.drawLine(
    image,
    x1: sx(layout.boxLeft),
    y1: sy(layout.boxTop),
    x2: sx(layout.boxRight),
    y2: sy(layout.boxTop),
    color: black,
    thickness: 3,
  );
  img.drawLine(
    image,
    x1: sx(layout.boxRight),
    y1: sy(layout.boxTop),
    x2: sx(layout.boxRight),
    y2: sy(layout.boxBottom),
    color: black,
    thickness: 3,
  );
  img.drawLine(
    image,
    x1: sx(layout.boxRight),
    y1: sy(layout.boxBottom),
    x2: sx(layout.boxLeft),
    y2: sy(layout.boxBottom),
    color: black,
    thickness: 3,
  );
  img.drawLine(
    image,
    x1: sx(layout.boxLeft),
    y1: sy(layout.boxBottom),
    x2: sx(layout.boxLeft),
    y2: sy(layout.boxTop),
    color: black,
    thickness: 3,
  );
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
  final black = img.ColorRgb8(0, 0, 0);
  for (var i = 0; i < 4; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % 4];
    img.drawLine(
      image,
      x1: a.$1.round(),
      y1: a.$2.round(),
      x2: b.$1.round(),
      y2: b.$2.round(),
      color: black,
      thickness: 3,
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

img.Image _renderForeignTemplateSheet() {
  final image = img.Image(width: 900, height: 1200);
  img.fill(image, color: img.ColorRgb8(246, 246, 246));
  final corners = <(double, double)>[
    (90, 85),
    (810, 85),
    (810, 1115),
    (90, 1115),
  ];
  final mapper = ProjectiveMapper.fromUnitSquare(corners)!;
  for (final (x, y) in corners) {
    img.fillRect(
      image,
      x1: x.round() - 22,
      y1: y.round() - 22,
      x2: x.round() + 22,
      y2: y.round() + 22,
      color: img.ColorRgb8(0, 0, 0),
    );
  }

  // This deliberately mirrors the first image-generated smoke sheet: valid
  // square markers, but a bubble grid that is not the Bayaz PDF template.
  const columns = [.33, .485, .638, .789];
  const rows = [.271, .339, .408, .474, .541, .607, .673, .736, .800, .864];
  for (var q = 0; q < 10; q++) {
    for (var c = 0; c < 4; c++) {
      final (x, y) = mapper.map(columns[c], rows[q]);
      img.drawCircle(
        image,
        x: x.round(),
        y: y.round(),
        radius: 20,
        color: img.ColorRgb8(15, 15, 15),
      );
      if ('ABCD'[c] == 'BDACBDCABD'[q]) {
        img.fillCircle(
          image,
          x: x.round(),
          y: y.round(),
          radius: 18,
          color: img.ColorRgb8(20, 20, 20),
        );
      }
    }
  }
  return image;
}

img.Image _renderAliasedTemplateSheet() {
  final layout = OmrTemplate.layoutFor(10);
  final image = img.Image(width: 900, height: 1200);
  img.fill(image, color: img.ColorRgb8(246, 246, 246));
  final corners = <(double, double)>[
    (90, 85),
    (810, 85),
    (810, 1115),
    (90, 1115),
  ];
  final mapper = ProjectiveMapper.fromUnitSquare(corners)!;
  for (final (x, y) in corners) {
    img.fillRect(
      image,
      x1: x.round() - 22,
      y1: y.round() - 22,
      x2: x.round() + 22,
      y2: y.round() + 22,
      color: img.ColorRgb8(0, 0, 0),
    );
  }

  // A deliberately wrong lookalike: it uses Bayaz's column spacing and row
  // pitch, but the entire bubble grid is shifted down by exactly one row.
  // A bubble-only verifier can therefore alias Q2..Q10 onto Q1..Q9 and
  // report ~36/40 matches even though this is not the Bayaz PDF template.
  for (var q = 1; q <= 10; q++) {
    for (var c = 0; c < 4; c++) {
      final (u, _) = layout.bubbleNorm(q, c);
      final (_, shiftedV) = layout.bubbleNorm(math.min(q + 1, 10), c);
      final v = q == 10 ? shiftedV + layout.rowPitch / layout.boxH : shiftedV;
      final (x, y) = mapper.map(u, v);
      img.drawCircle(
        image,
        x: x.round(),
        y: y.round(),
        radius: 20,
        color: img.ColorRgb8(15, 15, 15),
      );
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

  test(
    'template verification rejects a row-shifted alias grid without the Bayaz border',
    () {
      final result = OmrPipeline.scan(_renderAliasedTemplateSheet(), _key());

      expect(result.fiducialsFound, isTrue);
      expect(
        result.diagnostics!.templateMatchedBubbles,
        greaterThanOrEqualTo(32),
      );
      expect(result.diagnostics!.status, OmrScanStatus.rejected);
      expect(result.diagnostics!.failureCode, OmrFailureCode.templateMismatch);
    },
  );

  test(
    'pipeline rejects a registered sheet whose bubble grid is not the Bayaz template',
    () {
      final result = OmrPipeline.scan(_renderForeignTemplateSheet(), _key());

      expect(result.fiducialsFound, isTrue);
      expect(result.diagnostics!.status, OmrScanStatus.rejected);
      expect(result.diagnostics!.failureCode.name, 'templateMismatch');
      expect(result.correct, 0);
      expect(result.diagnostics!.toReport(), contains('template'));
    },
  );
}
