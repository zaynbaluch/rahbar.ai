import 'package:bayaz_ai/design_system/components/long_operation_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps rotating message copy while showing real progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: LongOperationPanel(
              primaryStatus: 'Preparing your classroom material…',
              messages: ['Finding teaching points…', 'Checking the structure…'],
              rotateEvery: Duration(seconds: 1),
              progress: 0.3,
              progressLabel: '3 of 10 questions ready',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Finding teaching points…'), findsOneWidget);
    expect(find.text('3 of 10 questions ready'), findsOneWidget);
    expect(find.text('Please keep this screen open.'), findsOneWidget);
    expect(
      find.text(
        'You can keep this screen open. Bayaz is working entirely on this device.',
      ),
      findsNothing,
    );
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.3);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Checking the structure…'), findsOneWidget);
  });
}
