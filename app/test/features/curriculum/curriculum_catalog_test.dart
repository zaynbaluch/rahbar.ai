import 'package:bayaz_ai/features/curriculum/curriculum_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog exposes only real supported class and subject modules', () {
    final curriculumClass = CurriculumCatalog.classByCode('6');

    expect(curriculumClass, isNotNull);
    expect(curriculumClass!.name, 'Class 6');
    expect(curriculumClass.subjects.single.code, 'general_science');
    expect(
      curriculumClass.subjects.single.moduleId,
      'curriculum.pk.class6.general_science',
    );
    expect(CurriculumCatalog.classByCode('7'), isNull);
  });

  test('class, subject, and module identifiers are unique', () {
    final classCodes = <String>{};
    final subjectKeys = <String>{};
    final moduleIds = <String>{};

    for (final curriculumClass in CurriculumCatalog.classes) {
      expect(classCodes.add(curriculumClass.code), isTrue);
      for (final subject in curriculumClass.subjects) {
        expect(subjectKeys.add('${curriculumClass.code}:${subject.code}'), isTrue);
        expect(moduleIds.add(subject.moduleId), isTrue);
      }
    }
  });
}
