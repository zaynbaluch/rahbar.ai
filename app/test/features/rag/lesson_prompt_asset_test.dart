import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lesson prompt is subject-neutral while staying source grounded', () async {
    final prompt = await rootBundle.loadString('assets/prompts/lesson_plan.md');

    expect(prompt, contains('**{{subject}},'));
    expect(prompt, contains('{{class}}'));
    expect(prompt, contains('CURRICULUM EXCERPTS'));
    expect(prompt, contains('Use **only** the facts in the CURRICULUM EXCERPTS'));
    expect(prompt.toLowerCase(), isNot(contains('science content')));
  });
}
