import 'package:bayaz_ai/features/omr/projective_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps all four unit-square corners exactly', () {
    final corners = <(double, double)>[
      (100, 80),
      (640, 150),
      (560, 900),
      (190, 790),
    ];
    final mapper = ProjectiveMapper.fromUnitSquare(corners)!;

    expectPoint(mapper.map(0, 0), corners[0]);
    expectPoint(mapper.map(1, 0), corners[1]);
    expectPoint(mapper.map(1, 1), corners[2]);
    expectPoint(mapper.map(0, 1), corners[3]);
  });

  test('recovers interior points from a known projective transform', () {
    (double, double) known(double u, double v) {
      final scale = 0.24 * u + 0.11 * v + 1;
      return (
        (510 * u + 65 * v + 90) / scale,
        (35 * u + 720 * v + 70) / scale,
      );
    }

    final mapper = ProjectiveMapper.fromUnitSquare([
      known(0, 0),
      known(1, 0),
      known(1, 1),
      known(0, 1),
    ])!;

    for (final point in [(0.2, 0.3), (0.5, 0.5), (0.8, 0.72)]) {
      expectPoint(mapper.map(point.$1, point.$2), known(point.$1, point.$2));
    }
  });

  test('rejects a degenerate quadrilateral', () {
    expect(
      ProjectiveMapper.fromUnitSquare(const [
        (0, 0),
        (1, 0),
        (2, 0),
        (3, 0),
      ]),
      isNull,
    );
  });
}

void expectPoint((double, double) actual, (double, double) expected) {
  expect(actual.$1, closeTo(expected.$1, 1e-7));
  expect(actual.$2, closeTo(expected.$2, 1e-7));
}
