import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rahbar_ai/features/library/saved_test.dart';

void main() {
  test('SavedTest survives a JSON round-trip and re-parses to a test', () {
    const raw = '''
Q1 [easy]
Where is bile produced?
A) Stomach
B) Liver
C) Mouth
D) Kidney
ANSWER: B
''';
    final t = SavedTest(
      id: '123',
      kind: 'mcq',
      topic: 'digestion',
      rawOutput: raw,
      createdAtMillis: 1720000000000,
      excerptTitles: const ['4.2 DIGESTIVE GLANDS'],
    );

    final back = SavedTest.fromJson(
        jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);

    expect(back.id, '123');
    expect(back.kind, 'mcq');
    expect(back.topic, 'digestion');
    expect(back.excerptTitles, ['4.2 DIGESTIVE GLANDS']);

    final parsed = back.toMcqTest();
    expect(parsed.count, 1);
    expect(parsed.questions.first.answer, 'B');
    expect(parsed.questions.first.text, 'Where is bile produced?');
  });

  test('fromJson tolerates missing optional fields', () {
    final back = SavedTest.fromJson({'id': 'x', 'rawOutput': ''});
    expect(back.kind, 'mcq');
    expect(back.excerptTitles, isEmpty);
  });
}
