/// GBNF grammar for the strict MCQ schema consumed by [McqParser].
///
/// Custom tests support exactly 5, 10 or 15 questions. Building the grammar for
/// the requested count keeps decoding constrained without silently truncating a
/// teacher's selection.
const String kMcqGrammarRoot = 'root';

String mcqGrammarForCount(int count) {
  if (count != 5 && count != 10 && count != 15) {
    throw ArgumentError.value(
      count,
      'count',
      'Supported MCQ counts are 5, 10, or 15.',
    );
  }
  final blocks = [for (var i = 1; i <= count; i++) 'block$i'].join(' ');
  final definitions = StringBuffer();
  for (var i = 1; i <= count; i++) {
    definitions.writeln(
      'block$i ::= "Q$i [" diff "]\\n" text "\\n" "A) " text "\\n" '
      '"B) " text "\\n" "C) " text "\\n" "D) " text "\\n" '
      '"ANSWER: " letter "\\n\\n"',
    );
  }
  final keyParts = [for (var i = 1; i <= count; i++) ' "$i=" letter'].join();
  return '''
root ::= $blocks key
$definitions
key ::= "KEY:"$keyParts "\\n"
diff ::= "easy" | "medium" | "hard"
letter ::= "A" | "B" | "C" | "D"
text ::= char char{0,199}
char ::= [^\\n]
''';
}

final String kMcqGrammar = mcqGrammarForCount(10);
