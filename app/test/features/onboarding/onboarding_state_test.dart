import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onboarding state round-trips and preserves progress', () {
    const state = OnboardingState(
      currentStep: 2,
      completed: false,
      teacherName: 'Teacher One',
      schoolName: 'School One',
      selectedClasses: ['6'],
      selectedSubjects: ['general_science'],
      offlineAiEnabled: true,
    );

    final restored = OnboardingState.fromJson(state.toJson());

    expect(restored.currentStep, 2);
    expect(restored.teacherName, 'Teacher One');
    expect(restored.offlineAiEnabled, isTrue);
    expect(restored.selectedSubjectsByClass['6'], ['general_science']);
  });

  test('copyWith can complete onboarding without losing selections', () {
    const state = OnboardingState(
      selectedClasses: ['6'],
      selectedSubjects: ['general_science'],
    );

    final completed = state.copyWith(completed: true, currentStep: 2);

    expect(completed.completed, isTrue);
    expect(completed.currentStep, 2);
    expect(completed.selectedClasses, ['6']);
    expect(completed.selectedSubjects, ['general_science']);
  });

  test('older analytics fields are ignored during migration', () {
    final restored = OnboardingState.fromJson({
      'current_step': 5,
      'teacher_name': 'Teacher One',
      'product_telemetry': true,
      'educational_analytics': true,
    });

    expect(restored.teacherName, 'Teacher One');
    expect(restored.schemaVersion, 2);
    expect(restored.selectedSubjectsByClass['6'], ['general_science']);
  });
}
