import 'mcq_parser.dart';

class GenerationProgress {
  const GenerationProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  double get fraction => total <= 0 ? 0 : (completed / total).clamp(0.0, 1.0);

  static GenerationProgress mcq(String output, int expectedCount) {
    if (expectedCount <= 0) {
      return const GenerationProgress(completed: 0, total: 0);
    }
    final parsed = McqParser.parse(output, expectedCount: expectedCount);
    return GenerationProgress(
      completed: parsed.completeCount.clamp(0, expectedCount),
      total: expectedCount,
    );
  }

  static GenerationProgress lesson(String output) {
    const orderedHeaders = <String>[
      'objectives',
      'materials',
      'revision starter',
      'engage',
      'explore',
      'explain',
      'socratic questions',
      'elaborate',
      'evaluate',
      'homework',
      'notes',
    ];
    final headerIndex = <String, int>{
      for (var i = 0; i < orderedHeaders.length; i++) orderedHeaders[i]: i,
    };
    final header = RegExp(r'^#{2,4}\s+(.+?)\s*$', caseSensitive: false);
    final minutes = RegExp(
      r'\s*\(\s*\d{1,3}\s*min(?:ute)?s?\s*\)\s*$',
      caseSensitive: false,
    );

    final recognized = <({int index, int line})>[];
    final lines = output.replaceAll('\r\n', '\n').split('\n');
    for (var line = 0; line < lines.length; line++) {
      final match = header.firstMatch(lines[line].trim());
      if (match == null) continue;
      final normalized = match
          .group(1)!
          .replaceAll(minutes, '')
          .trim()
          .toLowerCase();
      final index = headerIndex[normalized];
      if (index != null) recognized.add((index: index, line: line));
    }

    var completed = 0;
    for (var i = 0; i + 1 < recognized.length; i++) {
      final current = recognized[i];
      final next = recognized[i + 1];
      if (next.index <= current.index) continue;
      final hasBody = lines
          .sublist(current.line + 1, next.line)
          .any((line) => line.trim().isNotEmpty);
      if (hasBody) completed++;
    }

    return GenerationProgress(
      completed: completed.clamp(0, orderedHeaders.length),
      total: orderedHeaders.length,
    );
  }
}
