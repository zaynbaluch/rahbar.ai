import 'package:flutter_test/flutter_test.dart';
import 'package:rahbar_ai/features/generation/mcq_parser.dart';

/// Real Qwen3 1.7B output from the on-device grounded bake-off (ADR-003), the
/// shipping model/config. Trailing spaces on options are intentional (the model
/// emits them) — the parser must tolerate them.
const _qwen3 = '''
Q1 [easy]
What is the function of amylase, protease and lipase?
A) They break down carbohydrates, proteins and fats into smaller molecules
B) They absorb nutrients from food
C) They produce enzymes in the digestive system
D) They store energy in the body
ANSWER: A

Q2 [medium]
Where is bile produced?
A) In the stomach
B) In the small intestine
C) In the liver
D) In the mouth
ANSWER: C

Q3 [easy]
What happens to food during physical digestion?
A) It is broken down into smaller pieces
B) It is digested chemically
C) It is absorbed through the intestinal walls
D) It is stored in the stomach
ANSWER: A

Q4 [medium]
Which part of the digestive system absorbs nutrients?
A) Stomach
B) Small intestine
C) Large intestine
D) Esophagus
ANSWER: B

Q5 [hard]
Why is it important to chew food thoroughly?
A) To break down food into smaller pieces for easier digestion
B) To increase the surface area for better absorption
C) To prevent food from entering the lungs
D) All of the above
ANSWER: D

Q6 [medium]
What is the role of saliva in digestion?
A) It helps to break down carbohydrates
B) It contains enzymes that digest proteins
C) It softens food and starts the digestive process
D) It removes bacteria from the food
ANSWER: C

Q7 [easy]
Which organ is responsible for breaking down large protein molecules into smaller pieces?
A) Stomach
B) Small intestine
C) Large intestine
D) Liver
ANSWER: A

Q8 [medium]
What happens to food in the stomach?
A) It is mixed with enzymes and hydrochloric acid
B) It is absorbed through the intestinal walls
C) It is stored for four hours
D) It is broken down into sugars
ANSWER: A

Q9 [hard]
Why does diarrhea occur when there's an infection?
A) Because food is not properly digested
B) Because water and salts are not absorbed properly
C) Because the stomach becomes too acidic
D) All of the above
ANSWER: B

Q10 [medium]
What is the main function of the small intestine?
A) To absorb nutrients from food
B) To break down carbohydrates
C) To produce digestive enzymes
D) To store food temporarily
ANSWER: A

KEY: 1=A 2=C 3=A 4=B 5=D 6=C 7=A 8=A 9=B 10=A
''';

/// Degenerate Llama 3.2 1B output (temp 0.8) — empty question, leaked template
/// placeholder, an ANSWER without options. The parser must not crash and must
/// mark these incomplete rather than fabricate them.
const _degenerate = '''
Q1 [easy]
What is the main function of salivary glands?
A) To produce enzymes
B) To secrete saliva
C) To break down food
D) To absorb nutrients
ANSWER: B

Q2 [medium]

Q3 [easy]
<question text>
ANSWER: C
''';

void main() {
  group('McqParser', () {
    test('parses the real Qwen3 test into 10 complete questions', () {
      final t = McqParser.parse(_qwen3, topic: 'the human digestive system');
      expect(t.id, startsWith('GS6-'));
      expect(t.count, 10);
      expect(t.completeCount, 10);

      final q1 = t.questions.first;
      expect(q1.number, 1);
      expect(q1.difficulty, 'easy');
      expect(q1.text, 'What is the function of amylase, protease and lipase?');
      expect(q1.options.length, 4);
      expect(q1.options['A'],
          'They break down carbohydrates, proteins and fats into smaller molecules');
      expect(q1.answer, 'A');

      // Difficulty mix survives.
      expect(t.questions.where((q) => q.difficulty == 'hard').length, 2);
      // Answer key line reconstructed.
      expect(t.keyLine,
          '1=A 2=C 3=A 4=B 5=D 6=C 7=A 8=A 9=B 10=A');
    });

    test('preserves an existing paper ID when parsing saved model output', () {
      final t = McqParser.parse(
        _qwen3,
        topic: 'the human digestive system',
        testId: 'GS6-SAVED01',
      );
      expect(t.id, 'GS6-SAVED01');
    });

    test('KEY line back-fills answers when per-question ANSWER is missing', () {
      // Strip the inline ANSWER lines; the trailing KEY must still populate them.
      final noAnswers = _qwen3.replaceAll(RegExp(r'^ANSWER:.*\$', multiLine: true), '');
      final t = McqParser.parse(noAnswers);
      expect(t.questions[1].answer, 'C'); // Q2 from KEY
      expect(t.questions[8].answer, 'B'); // Q9 from KEY
    });

    test('tolerates degenerate output without crashing or fabricating', () {
      final t = McqParser.parse(_degenerate);
      // Q2 is empty → dropped; Q1 complete; Q3 has a placeholder + answer, no options.
      expect(t.questions.any((q) => q.number == 1 && q.isComplete), isTrue);
      expect(t.completeCount, 1);
      final q3 = t.questions.firstWhere((q) => q.number == 3);
      expect(q3.isComplete, isFalse); // no options → incomplete, not invented
      expect(q3.answer, 'C');
    });
  });
}
