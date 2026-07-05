// Smoke test for the Rahbar AI generation-spike screen.
//
// Verifies the app renders its core controls. It does NOT run inference —
// on-device generation requires the native engine + a downloaded model and is
// validated by driving the app on a device/emulator (see docs/07-3week-plan.md).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rahbar_ai/main.dart';

void main() {
  testWidgets('spike screen renders core controls', (WidgetTester tester) async {
    await tester.pumpWidget(const RahbarApp());

    expect(find.text('Rahbar AI · Generation Spike'), findsOneWidget);
    expect(find.text('Generate on-device'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // the prompt field
  });
}
