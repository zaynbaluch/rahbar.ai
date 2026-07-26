import 'package:bayaz_ai/features/generation/generated_output_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never reveals reasoning across any streaming split', () {
    const raw = '<think>private reasoning</think>Visible answer';
    for (var end = 1; end <= raw.length; end++) {
      final visible = GeneratedOutputSanitizer.sanitize(raw.substring(0, end));
      expect(visible, isNot(contains('private')));
      expect(visible, isNot(contains('<think')));
    }
    expect(
      GeneratedOutputSanitizer.sanitize(raw, finalOutput: true),
      'Visible answer',
    );
  });

  test('discards unterminated reasoning content', () {
    expect(
      GeneratedOutputSanitizer.sanitize(
        'Safe start<think>secret ending',
        finalOutput: true,
      ),
      'Safe start',
    );
  });

  test('removes internal source labels but keeps source text', () {
    const raw = '<<<CURRICULUM SOURCE 1: Plants>>>\n'
        'Plants need light.\n'
        '<<<END CURRICULUM SOURCE 1>>>\n'
        '[Excerpt 2 — Ch 1, Leaves]\n'
        'Leaves make food.';
    expect(
      GeneratedOutputSanitizer.sanitize(raw, finalOutput: true),
      'Plants need light.\nLeaves make food.',
    );
  });

  test('keeps ordinary angle brackets', () {
    expect(
      GeneratedOutputSanitizer.sanitize('Use 2 < 3 and <thing> as examples.'),
      'Use 2 < 3 and <thing> as examples.',
    );
  });

  test('rewrites unavailable lesson references', () {
    const raw = '- Draw Figure 2.1 from the textbook. (Excerpt 3)\n'
        '- Mention the diagram shown in Figure 4.2.\n'
        '3. (Refer to Excerpt 2)';
    expect(
      GeneratedOutputSanitizer.sanitize(
        raw,
        finalOutput: true,
        lessonPlan: true,
      ),
      '- Draw the board diagram.\n- Use a diagram on the board.',
    );
  });

  test('is idempotent', () {
    const raw = '<think>hidden</think>- Use Table 3.1. (Excerpt 2)';
    final once = GeneratedOutputSanitizer.sanitize(
      raw,
      finalOutput: true,
      lessonPlan: true,
    );
    final twice = GeneratedOutputSanitizer.sanitize(
      once,
      finalOutput: true,
      lessonPlan: true,
    );
    expect(twice, once);
  });
}
