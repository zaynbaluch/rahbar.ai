import 'teaching_context.dart';

class CurriculumModuleAssets {
  const CurriculumModuleAssets({
    required this.moduleId,
    required this.classCode,
    required this.subjectCode,
    required this.contentAsset,
    required this.ragAsset,
  });

  final String moduleId;
  final String classCode;
  final String subjectCode;
  final String contentAsset;
  final String ragAsset;
}

abstract final class CurriculumModuleRegistry {
  static const modules = <CurriculumModuleAssets>[
    CurriculumModuleAssets(
      moduleId: 'curriculum.pk.class6.general_science',
      classCode: '6',
      subjectCode: 'general_science',
      contentAsset: 'assets/content/content_pack.db',
      ragAsset: 'assets/rag/curriculum.db',
    ),
    CurriculumModuleAssets(
      moduleId: 'curriculum.pk.class7.general_science',
      classCode: '7',
      subjectCode: 'general_science',
      contentAsset:
          'assets/curricula/pk/class7/general_science/content_pack.db',
      ragAsset: 'assets/curricula/pk/class7/general_science/curriculum.db',
    ),
    CurriculumModuleAssets(
      moduleId: 'curriculum.pk.class7.history',
      classCode: '7',
      subjectCode: 'history',
      contentAsset: 'assets/curricula/pk/class7/history/content_pack.db',
      ragAsset: 'assets/curricula/pk/class7/history/curriculum.db',
    ),
  ];

  static CurriculumModuleAssets? byModuleId(String moduleId) {
    for (final module in modules) {
      if (module.moduleId == moduleId) return module;
    }
    return null;
  }

  static CurriculumModuleAssets resolve(TeachingContext? context) {
    final classCode = context?.classCode?.trim() ?? '';
    final subjectCode = context?.subjectCode?.trim() ?? '';
    if (classCode.isEmpty && subjectCode.isEmpty) return modules.first;
    if (classCode.isEmpty || subjectCode.isEmpty) {
      throw StateError(
        'Incomplete curriculum context: class=$classCode subject=$subjectCode',
      );
    }
    for (final module in modules) {
      if (module.classCode == classCode && module.subjectCode == subjectCode) {
        return module;
      }
    }
    throw StateError(
      'Unsupported curriculum context: class=$classCode subject=$subjectCode',
    );
  }
}
