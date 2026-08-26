import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/omr/omr_grader.dart';
import 'package:bayaz_ai/features/omr/omr_template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

McqTest _key() => McqTest(
  topic: 'Cells',
  expectedCount: 15,
  questions: [
    for (var i = 1; i <= 15; i++)
      McqQuestion(
        number: i,
        difficulty: 'easy',
        text: 'Q$i',
        options: const {'A': 'a', 'B': 'b', 'C': 'c', 'D': 'd'},
        answer: 'ABCD'[(i - 1) % 4],
      ),
  ],
);

img.Image _sheet() {
  final layout = OmrTemplate.layoutFor(15);
  const scale = 4.0;
  const pad = 16.0;
  final originX = layout.boxLeft - pad;
  final originY = layout.boxTop - pad;
  final image = img.Image(
    width: ((layout.boxW + pad * 2) * scale).round(),
    height: ((layout.boxH + pad * 2) * scale).round(),
  );
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);
  int sx(double x) => ((x - originX) * scale).round();
  int sy(double y) => ((y - originY) * scale).round();
  for (final (x, y) in layout.fiducials) {
    final half = (layout.fidSize * scale / 2).round();
    img.fillRect(
      image,
      x1: sx(x) - half,
      y1: sy(y) - half,
      x2: sx(x) + half,
      y2: sy(y) + half,
      color: black,
    );
  }
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
  final r = (layout.bubbleR * scale).round();
  for (var q = 1; q <= 15; q++) {
    for (var c = 0; c < 4; c++) {
      final (x, y) = layout.bubbleCenter(q, c);
      img.drawCircle(image, x: sx(x), y: sy(y), radius: r, color: black);
      if ('ABCD'[c] == 'ABCD'[(q - 1) % 4]) {
        img.fillCircle(image, x: sx(x), y: sy(y), radius: r - 1, color: black);
      }
    }
  }
  return image;
}

void main() {
  test('fifteen-question OMR layout fits and grades all rows', () {
    final layout = OmrTemplate.layoutFor(15);
    final (_, y) = layout.bubbleCenter(15, 3);
    expect(y + layout.bubbleR, lessThan(layout.boxBottom));

    final result = OmrGrader.grade(_sheet(), _key());
    expect(result.fiducialsFound, isTrue);
    expect(result.total, 15);
    expect(result.correct, 15);
  });
}
