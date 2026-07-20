import 'dart:math';

class BalancedMcqOptions {
  const BalancedMcqOptions({required this.options, required this.answer});

  final Map<String, String> options;
  final String answer;
}

/// Repositions correct answers across a generated paper while preserving each
/// option's text. Questions whose wording refers to option labels or position are
/// intentionally left unchanged because shuffling would alter their meaning.
abstract final class McqOptionBalancer {
  static const labels = ['A', 'B', 'C', 'D'];
  static final _positionDependent = RegExp(
    r'\b(all|none) of the above\b|\bboth\s+[a-d]\s+(and|&)\s+[a-d]\b|'
    r'\boption\s+[a-d]\b|\bstatements?\s+[a-d]\b',
    caseSensitive: false,
  );

  static bool canReorder(Map<String, String> options) =>
      options.length == 4 &&
      options.values.every((text) => !_positionDependent.hasMatch(text));

  static BalancedMcqOptions placeCorrectAt({
    required Map<String, String> options,
    required String answer,
    required String targetAnswer,
    required Random random,
  }) {
    if (!labels.contains(answer) ||
        !labels.contains(targetAnswer) ||
        !canReorder(options)) {
      return BalancedMcqOptions(
        options: Map<String, String>.from(options),
        answer: answer,
      );
    }

    final correctText = options[answer]!;
    final distractors = labels
        .where((label) => label != answer)
        .map((label) => options[label]!)
        .toList()
      ..shuffle(random);
    final result = <String, String>{};
    var distractorIndex = 0;
    for (final label in labels) {
      result[label] = label == targetAnswer
          ? correctText
          : distractors[distractorIndex++];
    }
    return BalancedMcqOptions(options: result, answer: targetAnswer);
  }

  static List<String> targetPositions(int count, Random random) {
    final targets = <String>[];
    while (targets.length < count) {
      final cycle = List<String>.from(labels)..shuffle(random);
      targets.addAll(cycle);
    }
    return targets.take(count).toList(growable: false);
  }
}
