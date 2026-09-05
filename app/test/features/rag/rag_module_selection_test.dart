import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/rag/rag_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Class 7 Science and History select distinct RAG assets', () {
    final science = RagService(
      teachingContext: const TeachingContext(
        classCode: '7',
        subjectCode: 'general_science',
      ),
    );
    final history = RagService(
      teachingContext: const TeachingContext(
        classCode: '7',
        subjectCode: 'history',
      ),
    );

    expect(science.moduleId, 'curriculum.pk.class7.general_science');
    expect(
      science.curriculumAsset,
      'assets/curricula/pk/class7/general_science/curriculum.db',
    );
    expect(history.moduleId, 'curriculum.pk.class7.history');
    expect(
      history.curriculumAsset,
      'assets/curricula/pk/class7/history/curriculum.db',
    );
    expect(history.curriculumAsset, isNot(science.curriculumAsset));
  });

  test('unknown coded RAG context is rejected instead of using Class 6', () {
    expect(
      () => RagService(
        teachingContext: const TeachingContext(
          classCode: '7',
          subjectCode: 'mathematics',
        ),
      ),
      throwsStateError,
    );
  });
}
