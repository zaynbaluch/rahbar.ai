import 'package:bayaz_ai/features/curriculum/curriculum_catalog.dart';
import 'package:bayaz_ai/features/curriculum/curriculum_module_registry.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every selectable catalog subject has a matching module asset entry', () {
    for (final curriculumClass in CurriculumCatalog.classes) {
      for (final subject in curriculumClass.subjects) {
        final module = CurriculumModuleRegistry.byModuleId(subject.moduleId);
        expect(module, isNotNull);
        expect(module!.classCode, curriculumClass.code);
        expect(module.subjectCode, subject.code);
      }
    }
  });

  test('Class 7 History resolves to its own content and RAG assets', () {
    final module = CurriculumModuleRegistry.resolve(
      const TeachingContext(classCode: '7', subjectCode: 'history'),
    );

    expect(module.moduleId, 'curriculum.pk.class7.history');
    expect(
      module.contentAsset,
      'assets/curricula/pk/class7/history/content_pack.db',
    );
    expect(
      module.ragAsset,
      'assets/curricula/pk/class7/history/curriculum.db',
    );
  });

  test('legacy context without codes keeps Class 6 General Science default', () {
    final module = CurriculumModuleRegistry.resolve(
      const TeachingContext(className: 'Class 6', subjectName: 'General Science'),
    );

    expect(module.moduleId, 'curriculum.pk.class6.general_science');
    expect(module.contentAsset, 'assets/content/content_pack.db');
    expect(module.ragAsset, 'assets/rag/curriculum.db');
  });

  test('unknown coded context never falls back to Class 6', () {
    expect(
      () => CurriculumModuleRegistry.resolve(
        const TeachingContext(classCode: '7', subjectCode: 'mathematics'),
      ),
      throwsStateError,
    );
  });
}
