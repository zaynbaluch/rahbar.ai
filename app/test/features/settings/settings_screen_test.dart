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
    expect(find.text('Data & support'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Teacher name'), findsOneWidget);
    expect(find.text('Classes & subjects'), findsOneWidget);
    expect(find.text('Offline AI'), findsOneWidget);
    expect(find.text('Data on this device'), findsOneWidget);
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
}
