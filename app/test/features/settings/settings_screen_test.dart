import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:bayaz_ai/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends OnboardingStore {
  _Store(this.state);
  OnboardingState state;
  @override
  Future<OnboardingState> read() async => state;
  @override
  Future<void> save(OnboardingState value) async => state = value;
}

void main() {
  testWidgets('settings is a maintenance area with the planned sections', (
    tester,
  ) async {
    final store = _Store(
      const OnboardingState(
        completed: true,
        teacherName: 'Ayesha',
        schoolName: 'Govt School',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(onboardingStore: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Teaching'), findsOneWidget);
    expect(find.text('Offline features'), findsOneWidget);
    expect(find.text('Data & support'), findsNothing);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Teacher name'), findsOneWidget);
    expect(find.text('Classes & subjects'), findsOneWidget);
    expect(find.text('Offline AI'), findsOneWidget);
    expect(find.text('Data on this device'), findsNothing);
    expect(find.text('Report a problem'), findsOneWidget);
    expect(find.text('Review setup'), findsNothing);
    expect(find.textContaining('model'), findsNothing);
  });

  testWidgets('teacher name can be edited without rerunning onboarding', (
    tester,
  ) async {
    final store = _Store(
      const OnboardingState(
        completed: true,
        teacherName: 'Ayesha',
        schoolName: 'Govt School',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(onboardingStore: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teacher name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sana');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.state.teacherName, 'Sana');
    expect(store.state.completed, isTrue);
  });

  testWidgets('selecting a one-subject class auto-selects its subject', (
    tester,
  ) async {
    final store = _Store(
      const OnboardingState(
        selectedClasses: [],
        selectedSubjects: [],
        selectedSubjectsByClass: {},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TeachingSettingsScreen(store: store, initial: store.state),
      ),
    );

    await tester.tap(find.text('Class 6'));
    await tester.pump();

    final subject = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'General Science'),
    );
    expect(subject.value, isTrue);
  });

  testWidgets('deselecting the sole subject also deselects its class', (
    tester,
  ) async {
    final store = _Store(
      const OnboardingState(
        selectedClasses: ['6'],
        selectedSubjects: ['general_science'],
        selectedSubjectsByClass: {
          '6': ['general_science'],
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TeachingSettingsScreen(store: store, initial: store.state),
      ),
    );

    await tester.tap(find.text('General Science'));
    await tester.pump();

    final classTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Class 6'),
    );
    expect(classTile.value, isFalse);
    expect(
      find.widgetWithText(CheckboxListTile, 'General Science'),
      findsNothing,
    );
  });

  testWidgets('a multi-subject class cannot lose its final subject', (
    tester,
  ) async {
    final store = _Store(
      const OnboardingState(
        selectedClasses: ['7'],
        selectedSubjects: ['history'],
        selectedSubjectsByClass: {
          '7': ['history'],
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TeachingSettingsScreen(store: store, initial: store.state),
      ),
    );

    await tester.tap(find.text('History'));
    await tester.pump();

    final history = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'History'),
    );
    final classTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Class 7'),
    );
    expect(history.value, isTrue);
    expect(classTile.value, isTrue);
  });

  testWidgets('an existing class with no subject is repaired on open', (
    tester,
  ) async {
    final store = _Store(
      const OnboardingState(
        selectedClasses: ['6'],
        selectedSubjects: [],
        selectedSubjectsByClass: {'6': []},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TeachingSettingsScreen(store: store, initial: store.state),
      ),
    );

    final subject = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'General Science'),
    );
    expect(subject.value, isTrue);
  });
}
