import 'package:bayaz_ai/features/curriculum/curriculum_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog exposes the three real supported class and subject modules', () {
    final class6 = CurriculumCatalog.classByCode('6');
    final class7 = CurriculumCatalog.classByCode('7');

    expect(class6, isNotNull);
    expect(class6!.name, 'Class 6');
    expect(class6.subjects, hasLength(1));
    expect(class6.subjects.single.code, 'general_science');
    expect(
      class6.subjects.single.moduleId,
      'curriculum.pk.class6.general_science',
    );

    expect(class7, isNotNull);
    expect(class7!.name, 'Class 7');
    expect(
      class7.subjects.map((subject) => subject.code).toList(),
      ['general_science', 'history'],
    );
    expect(
      class7.subjects.map((subject) => subject.moduleId).toList(),
      [
        'curriculum.pk.class7.general_science',
        'curriculum.pk.class7.history',
      ],
    );
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
