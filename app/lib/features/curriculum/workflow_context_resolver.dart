import '../onboarding/onboarding_store.dart';
import 'curriculum_catalog.dart';
import 'teaching_context.dart';

class WorkflowContextResolution {
  const WorkflowContextResolution({
    required this.context,
    required this.needsSelector,
    required this.showContextChange,
  });

  final TeachingContext? context;
  final bool needsSelector;
  final bool showContextChange;
}

abstract final class WorkflowContextResolver {
  static WorkflowContextResolution resolve({
    required OnboardingState state,
    required List<CurriculumClass> classes,
    TeachingContext? last,
  }) {
    final contexts = configuredContexts(state: state, classes: classes);
    final ambiguous = contexts.length > 1;
    final validLast = last == null
        ? null
        : contexts.cast<TeachingContext?>().firstWhere(
            (item) =>
                item?.classCode == last.classCode &&
                item?.subjectCode == last.subjectCode,
            orElse: () => null,
          );
    if (validLast != null) {
      return WorkflowContextResolution(
        context: validLast,
        needsSelector: false,
        showContextChange: ambiguous,
      );
    }
    if (contexts.length == 1) {
      return WorkflowContextResolution(
        context: contexts.single,
        needsSelector: false,
        showContextChange: false,
      );
    }
    return WorkflowContextResolution(
      context: null,
      needsSelector: contexts.isNotEmpty,
      showContextChange: ambiguous,
    );
  }

  static List<TeachingContext> configuredContexts({
    required OnboardingState state,
    required List<CurriculumClass> classes,
  }) {
    final out = <TeachingContext>[];
    for (final curriculumClass in classes) {
      if (!state.selectedClasses.contains(curriculumClass.code)) continue;
      final allowed =
          state.selectedSubjectsByClass[curriculumClass.code] ??
          state.selectedSubjects;
      for (final subject in curriculumClass.subjects) {
        if (!allowed.contains(subject.code)) continue;
        out.add(
          TeachingContext(
            classCode: curriculumClass.code,
            className: curriculumClass.name,
            subjectCode: subject.code,
            subjectName: subject.name,
          ),
        );
      }
    }
    return out;
  }
}
