import 'package:bayaz_ai/features/curriculum/curriculum_catalog.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_screen.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends OnboardingStore {
  OnboardingState state = const OnboardingState();
  @override Future<OnboardingState> read() async => state;
  @override Future<void> save(OnboardingState next) async => state = next;
}

const _classes = [
  CurriculumClass(code: '6', name: 'Class 6', subjects: [
    CurriculumSubject(code: 'science', name: 'Science', moduleId: 's6', description: ''),
    CurriculumSubject(code: 'math', name: 'Math', moduleId: 'm6', description: ''),
  ]),
  CurriculumClass(code: '7', name: 'Class 7', subjects: [
    CurriculumSubject(code: 'science', name: 'Science', moduleId: 's7', description: ''),
    CurriculumSubject(code: 'english', name: 'English', moduleId: 'e7', description: ''),
  ]),
];

void main() {
  testWidgets('onboarding contains no Offline AI setup step', (tester) async {
    final store = _Store();
    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline AI'), findsNothing);
    expect(find.text('Welcome to Bayaz'), findsOneWidget);
  });

  testWidgets('different subjects can be configured per class', (tester) async {
    final store = _Store();
    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(store: store, classes: _classes)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ayesha');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Select Class 7 in addition to the default Class 6.
    await tester.tap(find.text('Class 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Do you teach the same subjects in these classes?'), findsOneWidget);
    await tester.tap(find.text('No, they are different'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Subjects for Class 6'), findsOneWidget);
    await tester.tap(find.text('Math'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Next:'));
    await tester.pumpAndSettle();
    expect(find.text('Subjects for Class 7'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(store.state.completed, isTrue);
    expect(store.state.selectedSubjectsByClass['6'], contains('math'));
    expect(store.state.selectedSubjectsByClass['7'], contains('english'));
    expect(store.state.offlineAiEnabled, isTrue);
  });
}
