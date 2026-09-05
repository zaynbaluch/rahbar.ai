import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'custom MCQ prompt keeps questions standalone and student facing',
    () async {
      final prompt = await rootBundle.loadString('assets/prompts/mcq.md');

      expect(prompt, contains('Each question must stand alone for a student.'));
      expect(
        prompt,
        contains(
          'Never mention excerpts, sources, retrieval, chapter numbers, or section numbers',
        ),
      );
    },
  );
}
