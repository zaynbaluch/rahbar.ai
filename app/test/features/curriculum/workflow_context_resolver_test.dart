import 'package:bayaz_ai/features/curriculum/curriculum_catalog.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/curriculum/workflow_context_resolver.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const classes = [
    CurriculumClass(
      code: '6',
      name: 'Class 6',
      subjects: [
        CurriculumSubject(code: 'science', name: 'Science', moduleId: 's', description: ''),
        CurriculumSubject(code: 'math', name: 'Math', moduleId: 'm', description: ''),
      ],
    ),
    CurriculumClass(
      code: '7',
      name: 'Class 7',
      subjects: [
        CurriculumSubject(code: 'science', name: 'Science', moduleId: 's7', description: ''),
      ],
    ),
  ];

  test('one class and one subject resolves without a selector', () {
    const state = OnboardingState(
      selectedClasses: ['6'],
      selectedSubjectsByClass: {'6': ['science']},
    );
    final result = WorkflowContextResolver.resolve(state: state, classes: classes);
    expect(result.context?.classCode, '6');
    expect(result.context?.subjectCode, 'science');
    expect(result.needsSelector, isFalse);
    expect(result.showContextChange, isFalse);
  });

  test('a valid workflow-specific last context skips selection but keeps Change', () {
    const state = OnboardingState(
      selectedClasses: ['6'],
      selectedSubjectsByClass: {'6': ['science', 'math']},
    );
    const last = TeachingContext(classCode: '6', className: 'Class 6', subjectCode: 'math', subjectName: 'Math');
    final result = WorkflowContextResolver.resolve(state: state, classes: classes, last: last);
    expect(result.context?.subjectCode, 'math');
    expect(result.needsSelector, isFalse);
    expect(result.showContextChange, isTrue);
  });

  test('ambiguous configuration with no valid last context requests a selector', () {
    const state = OnboardingState(
      selectedClasses: ['6', '7'],
      selectedSubjectsByClass: {'6': ['science', 'math'], '7': ['science']},
    );
    final result = WorkflowContextResolver.resolve(state: state, classes: classes);
    expect(result.context, isNull);
    expect(result.needsSelector, isTrue);
    expect(result.showContextChange, isTrue);
  });
}
