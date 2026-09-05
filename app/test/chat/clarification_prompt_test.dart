import 'package:bayaz_ai/features/chat/clarification_context.dart';
import 'package:bayaz_ai/features/rag/rag_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a compact contextual prompt from recent turns', () {
    final prompt = ClarificationPromptBuilder.build(
      context: ClarificationContext(
        kind: 'lesson',
        title: 'Plants',
        material: List.filled(3000, 'A').join(),
      ),
      question: 'How should I explain photosynthesis?',
      retrieved: const [
        Chunk(
          id: '1',
          chapter: 2,
          title: 'Photosynthesis',
          text: 'Plants use light energy to make food.',
          pageStart: 10,
          pageEnd: 10,
          score: 0.9,
        ),
      ],
      history: const [
        ClarificationTurn(role: 'teacher', text: 'old 1'),
        ClarificationTurn(role: 'assistant', text: 'old 2'),
        ClarificationTurn(role: 'teacher', text: 'recent 1'),
        ClarificationTurn(role: 'assistant', text: 'recent 2'),
        ClarificationTurn(role: 'teacher', text: 'recent 3'),
        ClarificationTurn(role: 'assistant', text: 'recent 4'),
      ],
    );
    expect(prompt.system, contains('factual authority'));
    expect(prompt.user, contains('Photosynthesis'));
    expect(prompt.user, isNot(contains('old 1')));
    expect(prompt.user, contains('recent 4'));
    expect(prompt.user.length, lessThan(7000));
  });

  test('does not force source-search disclosure when excerpts are absent', () {
    final prompt = ClarificationPromptBuilder.build(
      context: const ClarificationContext(
        kind: 'lesson',
        title: 'Force',
        material: 'Students are learning about force.',
      ),
      question: 'What is force?',
      retrieved: const [],
      history: const [],
    );
    expect(prompt.user, contains('What is force?'));
    expect(prompt.user.toLowerCase(), isNot(contains('curriculum-grounded')));
    expect(prompt.user.toLowerCase(), isNot(contains('ungrounded')));
  });
}
