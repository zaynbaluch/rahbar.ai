import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated papers require all ten requested questions', () {
    final paper = McqParser.parse(
      List.generate(7, _questionBlock).join('\n'),
      topic: 'Cells',
    );

    expect(paper.expectedCount, 10);
    expect(paper.isReady, isFalse);
    expect(paper.validation.summary, contains('Expected 10 questions'));
  });

  test('verified short papers are ready when their expected count is met', () {
    final paper = McqTest(
      topic: 'Thin topic',
      expectedCount: 5,
      questions: List.generate(5, (index) => _question(index + 1)),
    );

    expect(paper.isReady, isTrue);
  });

  test('papers reject duplicate or out-of-order question numbers', () {
    final paper = McqTest(
      topic: 'Cells',
      expectedCount: 2,
      questions: [_question(1), _question(1)],
    );

    expect(paper.isReady, isFalse);
    expect(
      paper.validation.issues.any((issue) => issue.contains('Question numbers')),
      isTrue,
    );
  });

  test('questions require exactly four non-empty labelled options', () {
    final paper = McqTest(
      topic: 'Cells',
      expectedCount: 1,
      questions: [
        McqQuestion(
          number: 1,
          difficulty: 'easy',
          text: 'What is a cell?',
          options: const {'A': 'Unit of life', 'B': '', 'C': 'Gas', 'D': 'Rock'},
          answer: 'A',
        ),
      ],
    );

    expect(paper.isReady, isFalse);
  });

  test('expected count survives JSON storage', () {
    final paper = McqTest(
      id: 'paper-1',
      topic: 'Cells',
      expectedCount: 5,
      questions: List.generate(5, (index) => _question(index + 1)),
    );

    final restored = McqTest.fromJson(paper.toJson());

    expect(restored.expectedCount, 5);
    expect(restored.isReady, isTrue);
  });

  test('papers reject counts beyond the printable answer grid', () {
    final paper = McqTest(
      topic: 'Too many questions',
      expectedCount: 11,
      questions: List.generate(11, (index) => _question(index + 1)),
    );

    expect(paper.isReady, isFalse);
    expect(paper.validation.summary, contains('between 1 and 10'));
  });
}

String _questionBlock(int index) => '''
Q${index + 1} [easy]
Question ${index + 1}?
A) One
B) Two
C) Three
D) Four
ANSWER: A
''';

McqQuestion _question(int number) => McqQuestion(
      number: number,
      difficulty: 'easy',
      text: 'Question $number?',
      options: const {'A': 'One', 'B': 'Two', 'C': 'Three', 'D': 'Four'},
      answer: 'A',
    );
