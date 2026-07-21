import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/omr/omr_grader.dart';
import 'package:bayaz_ai/features/omr/omr_template.dart';

/// A test whose key is A B C D A B C D A B for Q1..Q10.
McqTest _key() => McqTest(
      topic: 'digestion',
      questions: [
        for (var i = 1; i <= 10; i++)
          McqQuestion(
            number: i,
            difficulty: 'easy',
            text: 'Q$i',
            options: const {'A': 'a', 'B': 'b', 'C': 'c', 'D': 'd'},
            answer: 'ABCD'[(i - 1) % 4],
          ),
      ],
    );

/// Render a synthetic photo of **just the answer box** (as the teacher shoots it):
/// the box region plus a framing margin, with fiducials at the box corners and the
/// bubbles inside. [pad] is the framing margin (points); [dx],[dy] shift everything
/// to simulate an off-center photo (tests the fiducial-relative mapping).
img.Image _renderSheet(Map<int, String> marks,
    {double scale = 4, double pad = 16, int dx = 0, int dy = 0}) {
  final originX = OmrTemplate.boxLeft - pad;
  final originY = OmrTemplate.boxTop - pad;
  final w = ((OmrTemplate.boxW + 2 * pad) * scale).round() + dx.abs() * 2;
  final h = ((OmrTemplate.boxH + 2 * pad) * scale).round() + dy.abs() * 2;
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);
  int sx(double x) => ((x - originX) * scale).round() + dx + dx.abs();
  int sy(double y) => ((y - originY) * scale).round() + dy + dy.abs();

  for (final (fx, fy) in OmrTemplate.fiducials) {
    final s = (OmrTemplate.fidSize * scale / 2).round();
    img.fillRect(im,
        x1: sx(fx) - s, y1: sy(fy) - s, x2: sx(fx) + s, y2: sy(fy) + s, color: black);
  }
  final r = (OmrTemplate.bubbleR * scale).round();
  for (var q = 1; q <= 10; q++) {
    for (var c = 0; c < 4; c++) {
      final (cx, cy) = OmrTemplate.bubbleCenter(q, c);
      img.drawCircle(im, x: sx(cx), y: sy(cy), radius: r, color: black);
      if (marks[q] == 'ABCD'[c]) {
        img.fillCircle(im, x: sx(cx), y: sy(cy), radius: r - 1, color: black);
      }
    }
  }
  return im;
}

void main() {
  group('OmrGrader', () {
    test('reads a perfectly-framed sheet and scores against the key', () {
      // Mark all correct except Q3 (mark A instead of C) and Q7 (leave blank).
      final marks = {
        for (var i = 1; i <= 10; i++) i: 'ABCD'[(i - 1) % 4],
      }..remove(7);
      marks[3] = 'A';

      final result = OmrGrader.grade(_renderSheet(marks), _key());

      expect(result.fiducialsFound, isTrue);
      expect(result.total, 10);
      expect(result.questions[0].marked, 'A'); // Q1 correct
      expect(result.questions[2].marked, 'A'); // Q3 marked A (key is C) -> wrong
      expect(result.questions[2].isRight, isFalse);
      expect(result.questions[6].marked, isNull); // Q7 blank
      expect(result.blank, 1);
      expect(result.correct, 8); // 10 - Q3(wrong) - Q7(blank)
    });

    test('is robust to an off-center photo (uses fiducials, not absolute px)', () {
      final marks = {for (var i = 1; i <= 10; i++) i: 'ABCD'[(i - 1) % 4]};
      final result = OmrGrader.grade(_renderSheet(marks, dx: 40, dy: 25), _key());
      expect(result.fiducialsFound, isTrue);
      expect(result.correct, 10); // all correct despite the offset
    });
  });

  test('clears the review warning after a teacher corrects an answer', () {
    const result = OmrResult(
      fiducialsFound: true,
      questions: [
        OmrQuestion(
          number: 1,
          marked: null,
          correct: 'A',
          fill: 0.1,
          confidence: 0.02,
        ),
      ],
    );

    expect(result.needsReview, 1);
    final corrected = result.withMark(1, 'A');
    expect(corrected.needsReview, 0);
    expect(corrected.questions.single.reviewed, isTrue);
  });

  test('refuses to grade a paper with a mismatched question count', () {
    final invalid = McqTest(
      topic: 'Incomplete',
      expectedCount: 2,
      questions: [_key().questions.first],
    );

    expect(
      () => OmrGrader.grade(img.Image(width: 1, height: 1), invalid),
      throwsStateError,
    );
  });

  additionalOmrTests();
}

img.Image _renderDoubleMarkSheet() {
  final image = _renderSheet({for (var i = 1; i <= 10; i++) i: 'ABCD'[(i - 1) % 4]});
  final scale = 4.0;
  const pad = 16.0;
  final originX = OmrTemplate.boxLeft - pad;
  final originY = OmrTemplate.boxTop - pad;
  int sx(double x) => ((x - originX) * scale).round();
  int sy(double y) => ((y - originY) * scale).round();
  final (cx, cy) = OmrTemplate.bubbleCenter(1, 1);
  img.fillCircle(
    image,
    x: sx(cx),
    y: sy(cy),
    radius: (OmrTemplate.bubbleR * scale).round() - 1,
    color: img.ColorRgb8(0, 0, 0),
  );
  return image;
}

void additionalOmrTests() {
  test('treats two similarly filled bubbles as ambiguous', () {
    final result = OmrGrader.grade(_renderDoubleMarkSheet(), _key());
    expect(result.fiducialsFound, isTrue);
    expect(result.questions.first.marked, isNull);
  });

  test('rejects dark corner regions without isolated square markers', () {
    final image = img.Image(width: 800, height: 1000);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final black = img.ColorRgb8(0, 0, 0);
    img.fillRect(image, x1: 0, y1: 0, x2: 250, y2: 250, color: black);
    img.fillRect(image, x1: 550, y1: 0, x2: 799, y2: 250, color: black);
    img.fillRect(image, x1: 550, y1: 750, x2: 799, y2: 999, color: black);
    img.fillRect(image, x1: 0, y1: 750, x2: 250, y2: 999, color: black);

    final result = OmrGrader.grade(image, _key());
    expect(result.fiducialsFound, isFalse);
  });
}
