// Smoke test for the Rahbar AI generation screen (app home).
//
// Verifies the app renders its core controls. It does NOT run inference —
// on-device generation requires the native engine + models and is validated by
// driving the app on a device (see docs/07-3week-plan.md).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rahbar_ai/main.dart';

void main() {
  testWidgets('generation screen renders core controls', (WidgetTester tester) async {
    await tester.pumpWidget(const RahbarApp());

    expect(find.text('Rahbar AI'), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);
    expect(find.text('MCQ Test'), findsOneWidget);
    expect(find.text('Lesson Plan'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // the topic field
  });
}
