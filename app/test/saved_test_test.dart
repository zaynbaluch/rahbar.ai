import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bayaz_ai/features/generation/lesson_plan.dart';
import 'package:bayaz_ai/features/library/saved_test.dart';

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
    expect(parsed.id, '123');
    expect(parsed.count, 1);
    expect(parsed.questions.first.answer, 'B');
    expect(parsed.questions.first.text, 'Where is bile produced?');
  });

  test('fromJson tolerates missing optional fields', () {
    final back = SavedTest.fromJson({'id': 'x', 'rawOutput': ''});
    expect(back.kind, 'mcq');
    expect(back.excerptTitles, isEmpty);
  });

  test('structured lesson plans survive storage and reopen as a plan', () {
    const plan = LessonPlan(
      topicId: 'topic-1',
      topic: 'Mixtures',
      slos: ['Identify common mixtures.'],
      sections: [
        PlanSection(
          id: 'engage-a',
          section: 'engage',
          variantLabel: 'quick-demo',
          minutes: 5,
          body: 'Show sand mixed with iron filings.',
          materials: ['sand', 'iron filings'],
        ),
      ],
    );
    final saved = SavedTest(
      id: 'lesson-1',
      kind: 'lesson',
      topic: plan.topic,
      topicId: plan.topicId,
      createdAtMillis: 1720000000000,
      contentJson: plan.toJson(),
    );

    final back = SavedTest.fromJson(
      jsonDecode(jsonEncode(saved.toJson())) as Map<String, dynamic>,
    );
    final reopened = back.toLessonPlan();

    expect(reopened, isNotNull);
    expect(reopened!.topic, 'Mixtures');
    expect(reopened.sections.single.id, 'engage-a');
    expect(reopened.materials, ['iron filings', 'sand']);
  });

  test('older structured tests fall back to the saved file ID', () {
    final saved = SavedTest(
      id: 'legacy-paper-id',
      kind: 'mcq',
      topic: 'Digestion',
      createdAtMillis: 1720000000000,
      contentJson: {
        'topic': 'Digestion',
        'questions': const <Map<String, dynamic>>[],
      },
    );

    expect(saved.toMcqTest().id, 'legacy-paper-id');
  });
}
