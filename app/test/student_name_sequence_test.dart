import 'package:bayaz_ai/features/omr/student_name_sequence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts with the first student when no results exist', () {
    expect(StudentNameSequence.nextName(const []), 'Student 1');
  });

  test('continues after the highest saved default name', () {
    expect(
      StudentNameSequence.nextName(
        const ['Student 1', 'Ayesha', 'Student 3', 'student 2'],
      ),
      'Student 4',
    );
  });

  test('ignores names that only contain a number', () {
    expect(
      StudentNameSequence.nextName(const ['Roll 18', 'Student helper']),
      'Student 1',
    );
  });
}
