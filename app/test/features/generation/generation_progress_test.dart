import 'package:bayaz_ai/features/generation/generation_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MCQ progress counts only structurally complete streamed questions', () {
    const partial = '''
Q1 [easy]
What is one?
A) A
B) B
C) C
D) D
ANSWER: A

Q2 [medium]
What is two?
A) A
B) B
C) C
''';

    final progress = GenerationProgress.mcq(partial, 10);

    expect(progress.completed, 1);
    expect(progress.total, 10);
    expect(progress.fraction, 0.1);
  });

  test('lesson progress counts closed structured sections', () {
    const partial = '''
### Objectives
- Identify the parts.

### Materials
- Chalk

### Revision starter (5 min)
What did we learn yesterday?
''';

    final progress = GenerationProgress.lesson(partial);

    expect(progress.completed, 2);
    expect(progress.total, 11);
    expect(progress.fraction, closeTo(2 / 11, 0.0001));
  });
}
