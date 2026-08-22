// Parses the model's strict, delimited MCQ output (see prompts/mcq.md) into a
// structured test + answer key. The format is machine-parseable by design so the
// app can store the key and later grade OMR sheets by test ID — no SLM at grading
// time. The parser is deliberately tolerant of small format drift (trailing
// spaces, code fences, `A.`/`A)` option markers, missing blank lines) because a
// 1–2 B model won't be byte-perfect.

/// One multiple-choice question.
class McqQuestion {
  const McqQuestion({
    required this.number,
    required this.difficulty,
    required this.text,
    required this.options,
    required this.answer,
    this.itemId,
  });

  final int number;
  final String difficulty; // 'easy' | 'medium' | 'hard' | ''
  final String text;
  final Map<String, String> options; // 'A'..'D' -> option text
  final String? answer; // 'A'..'D', or null if unparseable

  /// The content-pack item this was sampled from, when it came from the bank rather
  /// than the on-device model. Lets the library exclude questions a teacher has already
  /// used when they draw a second test on the same topic.
  final String? itemId;

  bool get isComplete =>
      text.isNotEmpty && options.length == 4 && answer != null;

  Map<String, dynamic> toJson() => {
        'number': number,
        'difficulty': difficulty,
        'text': text,
        'options': options,
        'answer': answer,
        if (itemId != null) 'itemId': itemId,
      };

  factory McqQuestion.fromJson(Map<String, dynamic> j) => McqQuestion(
        number: j['number'] as int,
        difficulty: j['difficulty'] as String? ?? '',
        text: j['text'] as String? ?? '',
        options: (j['options'] as Map).map((k, v) => MapEntry('$k', '$v')),
        answer: j['answer'] as String?,
        itemId: j['itemId'] as String?,
      );
}

/// A parsed test: the questions plus a coverage flag for the UI/QA.
class McqTest {
  const McqTest({required this.topic, required this.questions});

  final String topic;
  final List<McqQuestion> questions;

  int get count => questions.length;
  int get completeCount => questions.where((q) => q.isComplete).length;

  /// Answer key as "1=A 2=C …" (the OMR-gradable representation).
  String get keyLine => questions
      .map((q) => '${q.number}=${q.answer ?? '?'}')
      .join(' ');

  /// The bank items used, so a re-draw on the same topic can avoid repeating them.
  Set<String> get itemIds =>
      questions.map((q) => q.itemId).whereType<String>().toSet();

  Map<String, dynamic> toJson() => {
        'topic': topic,
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  factory McqTest.fromJson(Map<String, dynamic> j) => McqTest(
        topic: j['topic'] as String? ?? '',
        questions: (j['questions'] as List? ?? [])
            .map((e) => McqQuestion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class McqParser {
  // Q1 [easy]  /  Q1  /  Q 1 [medium]  — captures number + optional difficulty.
  static final RegExp _header = RegExp(
    r'^\s*Q\s*(\d+)\s*(?:\[\s*(easy|medium|hard)\s*\])?\s*$',
    caseSensitive: false,
    multiLine: true,
  );
  // A) text  /  A. text  /  A - text
  static final RegExp _option = RegExp(
    r'^\s*([A-D])\s*[\)\.\-:]\s*(.+?)\s*$',
    caseSensitive: false,
  );
  static final RegExp _answer = RegExp(
    r'^\s*ANSWER\s*[:=]?\s*\(?\s*([A-D])',
    caseSensitive: false,
  );
  static final RegExp _keyLine = RegExp(
    r'^\s*KEY\s*[:=]\s*(.+)$',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _keyPair = RegExp(r'(\d+)\s*[=:]\s*([A-D])', caseSensitive: false);

  /// Parse [raw] model output into a structured [McqTest].
  static McqTest parse(String raw, {String topic = ''}) {
    // Drop markdown code fences the model sometimes wraps the block in.
    final text = raw.replaceAll(RegExp(r'^\s*```.*$', multiLine: true), '');

    // Fallback answer key from a trailing "KEY: 1=A 2=C …" line, if present.
    final keyMap = <int, String>{};
    final keyMatch = _keyLine.firstMatch(text);
    if (keyMatch != null) {
      for (final m in _keyPair.allMatches(keyMatch.group(1)!)) {
        keyMap[int.parse(m.group(1)!)] = m.group(2)!.toUpperCase();
      }
    }

    // Split the body into per-question segments at each "Q<n>" header.
    final headers = _header.allMatches(text).toList();
    final questions = <McqQuestion>[];
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i];
      final number = int.parse(h.group(1)!);
      final difficulty = (h.group(2) ?? '').toLowerCase();
      final bodyStart = h.end;
      final bodyEnd = i + 1 < headers.length ? headers[i + 1].start : text.length;
      final body = text.substring(bodyStart, bodyEnd);

      final q = _parseBody(number, difficulty, body, keyMap[number]);
      if (q != null) questions.add(q);
    }
    return McqTest(topic: topic, questions: questions);
  }

  static McqQuestion? _parseBody(
      int number, String difficulty, String body, String? keyAnswer) {
    final options = <String, String>{};
    final questionLines = <String>[];
    String? answer;
    var seenOption = false;

    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Stop this question at the KEY line if it landed inside the last block.
      if (RegExp(r'^\s*KEY\s*[:=]', caseSensitive: false).hasMatch(trimmed)) break;

      final a = _answer.firstMatch(trimmed);
      if (a != null) {
        answer = a.group(1)!.toUpperCase();
        continue;
      }
      final o = _option.firstMatch(trimmed);
      if (o != null) {
        options[o.group(1)!.toUpperCase()] = o.group(2)!.trim();
        seenOption = true;
        continue;
      }
      // Question text is whatever precedes the options (an option-less line after
      // options begin is dropped, e.g. a stray "<question text>" placeholder).
      if (!seenOption) questionLines.add(trimmed);
    }

    if (questionLines.isEmpty && options.isEmpty) return null; // empty block
    return McqQuestion(
      number: number,
      difficulty: difficulty,
      text: questionLines.join(' ').trim(),
      options: options,
      answer: answer ?? keyAnswer,
    );
  }
}
