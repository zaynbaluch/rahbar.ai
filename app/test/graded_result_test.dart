import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bayaz_ai/features/omr/graded_result.dart';
import 'package:bayaz_ai/features/omr/omr_grader.dart';

void main() {
  test('GradedResult from an OmrResult captures score + marks and round-trips', () {
    final omr = OmrResult(
      fiducialsFound: true,
      questions: [
        const OmrQuestion(number: 1, marked: 'A', correct: 'A', fill: 0.9, confidence: 0.5), // right
        const OmrQuestion(number: 2, marked: 'C', correct: 'B', fill: 0.8, confidence: 0.5), // wrong
        const OmrQuestion(number: 3, marked: null, correct: 'D', fill: 0.1, confidence: 0.0), // blank
      ],
    );

    final g = GradedResult.fromGrading(
      testId: 'GS6-41CD',
      testTopic: 'digestion',
      studentName: 'Ayesha',
      result: omr,
    );
    expect(g.correct, 1);
    expect(g.total, 3);
    expect(g.marks, 'A|C|'); // Q3 blank -> empty
    expect(g.correctAnswers, 'A|B|D');
    expect(g.pct, 33);

    final back = GradedResult.fromJson(
        jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
    expect(back.studentName, 'Ayesha');
    expect(back.testId, 'GS6-41CD');
    expect(back.correct, 1);
    expect(back.marks, 'A|C|');
  });
}
