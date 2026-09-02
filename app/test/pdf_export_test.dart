import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bayaz_ai/features/export/pdf_export.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';

// Real Qwen3 1.7B digestive-system test (same fixture as mcq_parser_test).
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

void main() {
  test('builds a non-trivial PDF and writes it for visual inspection', () async {
    final test = McqParser.parse(_qwen3, topic: 'the human digestive system');
    final bytes = await PdfExport.build(test);
    expect(bytes.lengthInBytes, greaterThan(2000));

    // Dump to a stable path so the harness can rasterize + inspect the layout.
    final out = Platform.environment['PDF_OUT'] ?? '/tmp/bayaz_test.pdf';
    File(out).writeAsBytesSync(bytes);
  });

  test(
    'refuses to export a paper that does not match its expected count',
    () async {
      final paper = McqTest(
        topic: 'Incomplete paper',
        expectedCount: 2,
        questions: const [
          McqQuestion(
            number: 1,
            difficulty: 'easy',
            text: 'Only question',
            options: {'A': 'One', 'B': 'Two', 'C': 'Three', 'D': 'Four'},
            answer: 'A',
          ),
        ],
      );

      await expectLater(
        PdfExport.build(paper),
        throwsA(isA<InvalidMcqPaperException>()),
      );
    },
  );

  test('lesson PDF teaching header comes from route context', () {
    expect(
      PdfExport.teachingLabel(
        const TeachingContext(className: 'Class 8', subjectName: 'Biology'),
      ),
      'Class 8 · Biology',
    );
    expect(PdfExport.teachingLabel(null), isEmpty);
  });
}
