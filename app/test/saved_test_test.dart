import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bayaz_ai/features/generation/lesson_plan.dart';
import 'package:bayaz_ai/features/generation/mcq_parser.dart';
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
      source: SavedContentSource.customAi,
      topic: 'digestion',
      rawOutput: raw,
      createdAtMillis: 1720000000000,
      excerptTitles: const ['4.2 DIGESTIVE GLANDS'],
    );

    final back = SavedTest.fromJson(
      jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>,
    );

    expect(back.id, '123');
    expect(back.kind, 'mcq');
    expect(back.topic, 'digestion');
    expect(back.source, SavedContentSource.customAi);
    expect(back.fromPack, isFalse);
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
      source: SavedContentSource.curriculumPack,
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

  test('reused item metadata survives structured test storage', () {
    final paper = McqTest(
      id: 'paper-with-repeat',
      topic: 'Cells',
      reusedItemIds: const {'item-1'},
      questions: const [
        McqQuestion(
          number: 1,
          difficulty: 'easy',
          text: 'What is a cell?',
          options: {'A': 'Unit of life', 'B': 'Rock', 'C': 'Gas', 'D': 'Metal'},
          answer: 'A',
          itemId: 'item-1',
        ),
      ],
    );
    final restored = McqTest.fromJson(paper.toJson());

    expect(restored.reusedItemIds, {'item-1'});
    expect(restored.itemIds, {'item-1'});
  });

  test('older structured tests fall back to the saved file ID', () {
    final saved = SavedTest(
      id: 'legacy-paper-id',
      kind: 'mcq',
      source: SavedContentSource.legacy,
      topic: 'Digestion',
      createdAtMillis: 1720000000000,
      contentJson: {
        'topic': 'Digestion',
        'questions': const <Map<String, dynamic>>[],
      },
    );

    expect(saved.toMcqTest().id, 'legacy-paper-id');
  });

  test('legacy pack entries infer curriculum provenance only with a topic ID', () {
    final saved = SavedTest.fromJson({
      'id': 'old-pack',
      'kind': 'mcq',
      'topic': 'Cells',
      'topicId': 'cells',
      'contentJson': jsonEncode({
        'topic': 'Cells',
        'questions': const <Map<String, dynamic>>[],
      }),
    });

    expect(saved.source, SavedContentSource.curriculumPack);
    expect(saved.fromPack, isTrue);
  });

  test('structured legacy entries without a topic ID are not marked verified', () {
    final saved = SavedTest.fromJson({
      'id': 'old-custom',
      'kind': 'mcq',
      'topic': 'Cells',
      'contentJson': jsonEncode({
        'topic': 'Cells',
        'questions': const <Map<String, dynamic>>[],
      }),
    });

    expect(saved.source, SavedContentSource.legacy);
    expect(saved.fromPack, isFalse);
    expect(saved.toMcqTest().expectedCount, 10);
  });


  test('structured custom output keeps its review provenance', () {
    final saved = SavedTest(
      id: 'custom-paper',
      kind: 'mcq',
      source: SavedContentSource.customAi,
      topic: 'Cells',
      createdAtMillis: 1720000000000,
      contentJson: {
        'topic': 'Cells',
        'expectedCount': 10,
        'questions': const <Map<String, dynamic>>[],
      },
    );

    final restored = SavedTest.fromJson(saved.toJson());

    expect(restored.source, SavedContentSource.customAi);
    expect(restored.fromCustomAi, isTrue);
    expect(restored.fromPack, isFalse);
  });
}
