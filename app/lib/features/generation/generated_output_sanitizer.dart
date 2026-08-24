/// Removes model-only reasoning and retrieval scaffolding before generated text
/// is displayed or saved.
abstract final class GeneratedOutputSanitizer {
  static const String _thinkOpen = '<think>';
  static const String _thinkClose = '</think>';

  static String sanitize(
    String value, {
    bool finalOutput = false,
    bool lessonPlan = false,
  }) {
    var cleaned = _removeReasoning(value, finalOutput: finalOutput);
    cleaned = _removeSourceScaffolding(cleaned);
    if (lessonPlan) cleaned = _sanitizeLessonReferences(cleaned);
    return cleaned.trimLeft();
  }

  static String _removeReasoning(
    String value, {
    required bool finalOutput,
  }) {
    final lower = value.toLowerCase();
    final visible = StringBuffer();
    var cursor = 0;
    var insideReasoning = false;

    while (cursor < value.length) {
      if (insideReasoning) {
        final close = lower.indexOf(_thinkClose, cursor);
        if (close < 0) return visible.toString();
        cursor = close + _thinkClose.length;
        insideReasoning = false;
        continue;
      }

      final open = lower.indexOf(_thinkOpen, cursor);
      if (open < 0) {
        var tail = value.substring(cursor);
        final withheld = _partialOpeningTagLength(tail);
        if (withheld > 0) {
          tail = tail.substring(0, tail.length - withheld);
          if (finalOutput) {
            // A truncated opening tag at the end of a failed generation is safer
            // to discard than to show as teacher-facing text.
          }
        }
        visible.write(tail.replaceAll(
          RegExp(RegExp.escape(_thinkClose), caseSensitive: false),
          '',
        ));
        break;
      }

      visible.write(value.substring(cursor, open));
      cursor = open + _thinkOpen.length;
      insideReasoning = true;
    }
    return visible.toString();
  }

  static int _partialOpeningTagLength(String value) {
    final lower = value.toLowerCase();
    final max = lower.length < _thinkOpen.length - 1
        ? lower.length
        : _thinkOpen.length - 1;
    for (var length = max; length > 0; length--) {
      if (_thinkOpen.startsWith(lower.substring(lower.length - length))) {
        return length;
      }
    }
    return 0;
  }

  static String _removeSourceScaffolding(String value) {
    var cleaned = value.replaceAll(
      RegExp(
        r'^[ \t]*(?:\[Excerpt\s+\d+[^\]]*\]|<<<(?:END\s+)?CURRICULUM\s+SOURCE[^>]*>>>)[ \t]*\r?\n?',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*\((?:ref(?:er)?\.?\s*(?:to\s*)?)?excerpts?\s+\d+\)',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s+in\s+(?:ref(?:er)?\.?\s*(?:to\s*)?)?excerpts?\s+\d+',
        caseSensitive: false,
      ),
      '',
    );
    return cleaned;
  }

  static String _sanitizeLessonReferences(String value) {
    const number = r'\d+(?:\.\d+)*';
    const figure =
        r'figures?\s*' '$number' r'(?:\s*(?:and|,|&)\s*(?:figures?\s*)?' '$number' r')*';
    const table =
        r'tables?\s*' '$number' r'(?:\s*(?:and|,|&)\s*(?:tables?\s*)?' '$number' r')*';

    final parenthetical = RegExp(
      r'\s*\([^)]*\b(?:' '$figure|$table' r')\b[^)]*\)',
      caseSensitive: false,
    );
    final previousLessons = RegExp(
      r'\s*\([^)]*\bprevious lessons?\b[^)]*\)',
      caseSensitive: false,
    );
    final diagramInFigure = RegExp(
      r'\bthe diagram (?:shown |given )?in ' '$figure',
      caseSensitive: false,
    );
    final chartInFigure = RegExp(
      r'\bthe chart (?:shown |given )?in ' '$figure',
      caseSensitive: false,
    );
    final figurePhrase = RegExp(
      r'\b' '$figure' r'(?:\s+from the textbook)?',
      caseSensitive: false,
    );
    final tablePhrase = RegExp(
      r'\b' '$table' r'(?:\s+from the textbook)?',
      caseSensitive: false,
    );

    final lines = <String>[];
    for (var line in value.split('\n')) {
      line = line.replaceAll(parenthetical, '');
      line = line.replaceAll(previousLessons, '');
      line = line.replaceAll(diagramInFigure, 'a diagram on the board');
      line = line.replaceAll(chartInFigure, 'a chart on the board');
      line = line.replaceAll(figurePhrase, 'the board diagram');
      line = line.replaceAll(tablePhrase, 'the board diagram');
      line = line.replaceAll(
        RegExp(
          r'\bMention(?=\s+(?:the board diagram|an? (?:diagram|chart) on the board))',
          caseSensitive: false,
        ),
        'Use',
      );
      line = line.replaceAll(
        RegExp(r'\s+from the textbook\b', caseSensitive: false),
        '',
      );
      line = line.replaceAll(RegExp(r'\s+([.,;:])'), r'$1');
      line = line.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trimRight();
      if (RegExp(r'^(?:[-*•]|\d+[.)]?)$').hasMatch(line.trim())) continue;
      lines.add(line);
    }
    return lines.join('\n').trim();
  }
}
