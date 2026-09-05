class CurriculumSubject {
  const CurriculumSubject({
    required this.code,
    required this.name,
    required this.moduleId,
    required this.description,
  });

  final String code;
  final String name;
  final String moduleId;
  final String description;
}

class CurriculumClass {
  const CurriculumClass({
    required this.code,
    required this.name,
    required this.subjects,
  });

  final String code;
  final String name;
  final List<CurriculumSubject> subjects;
}

abstract final class CurriculumCatalog {
  static const classes = <CurriculumClass>[
    CurriculumClass(
      code: '6',
      name: 'Class 6',
      subjects: [
        CurriculumSubject(
          code: 'general_science',
          name: 'General Science',
          moduleId: 'curriculum.pk.class6.general_science',
          description: 'Verified offline lessons and assessment items.',
        ),
      ],
    ),
    CurriculumClass(
      code: '7',
      name: 'Class 7',
      subjects: [
        CurriculumSubject(
          code: 'general_science',
          name: 'General Science',
          moduleId: 'curriculum.pk.class7.general_science',
          description: 'Verified offline lessons and assessment items.',
        ),
        CurriculumSubject(
          code: 'history',
          name: 'History',
          moduleId: 'curriculum.pk.class7.history',
          description: 'Verified offline lessons and assessment items.',
        ),
      ],
    ),
  ];

  static CurriculumClass? classByCode(String code) {
    for (final item in classes) {
      if (item.code == code) return item;
    }
    return null;
  }
}
