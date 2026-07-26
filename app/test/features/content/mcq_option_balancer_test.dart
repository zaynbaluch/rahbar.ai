import 'dart:math';

import 'package:bayaz_ai/features/content/mcq_option_balancer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('target positions are balanced to within one question', () {
    final targets = McqOptionBalancer.targetPositions(10, Random(7));
    final counts = <String, int>{
      for (final label in McqOptionBalancer.labels)
        label: targets.where((value) => value == label).length,
    };

    final highest = counts.values.reduce((a, b) => a > b ? a : b);
    final lowest = counts.values.reduce((a, b) => a < b ? a : b);
    expect(highest - lowest, lessThanOrEqualTo(1));
  });

  test('moves the correct option and preserves every option text', () {
    final options = {
      'A': 'first distractor',
      'B': 'correct content',
      'C': 'second distractor',
      'D': 'third distractor',
    };

    final result = McqOptionBalancer.placeCorrectAt(
      options: options,
      answer: 'B',
      targetAnswer: 'D',
      random: Random(2),
    );

    expect(result.answer, 'D');
    expect(result.options['D'], 'correct content');
    expect(result.options.values.toSet(), options.values.toSet());
  });

  test('does not reorder position-dependent options', () {
    final options = {
      'A': 'One',
      'B': 'Two',
      'C': 'Three',
      'D': 'All of the above',
    };

    final result = McqOptionBalancer.placeCorrectAt(
      options: options,
      answer: 'D',
      targetAnswer: 'A',
      random: Random(2),
    );

    expect(result.answer, 'D');
    expect(result.options, options);
  });
}
