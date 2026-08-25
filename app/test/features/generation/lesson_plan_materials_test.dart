import 'package:bayaz_ai/features/generation/lesson_plan.dart';
import 'package:bayaz_ai/features/generation/lesson_plan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Long enough that it cannot fit on one line of a narrow phone, which is what
/// used to push the section card past the right edge of the screen.
const _longMaterial =
    'One clear glass jar of water per group, plus a spoon of salt and a '
    'teaspoon of cooking oil for the floating and sinking comparison';

const _plan = LessonPlan(
  topicId: 'topic-1',
  topic: 'Mixtures and solutions',
  slos: ['Separate a mixture using everyday materials.'],
  sections: [
    PlanSection(
      id: 'explore-group-work',
      section: 'explore',
      variantLabel: 'group-work',
      minutes: 12,
      body: 'Groups test which everyday substances dissolve in water.',
      materials: [_longMaterial, 'Chalk'],
    ),
  ],
);

void main() {
  testWidgets('a long section material wraps instead of overflowing', (
    tester,
  ) async {
    // 360 logical pixels wide is a small phone, and width is what decides a
    // horizontal overflow. The viewport is left tall so the lazy list builds
    // the section card instead of the test having to scroll to it.
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final overflows = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      overflows.add(details.exceptionAsString());
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LessonPlanDocument(plan: _plan)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      overflows.where((message) => message.contains('overflowed')),
      isEmpty,
    );

    // The whole sentence stays in the tree and stays readable: it is laid out
    // over several lines rather than clipped or shrunk away.
    final material = find.text(_longMaterial);
    expect(material, findsOneWidget);
    final rendered = tester.renderObject<RenderParagraph>(material);
    expect(rendered.size.width, lessThanOrEqualTo(360));
    expect(rendered.text.toPlainText(), _longMaterial);
    // Laid out with no width limit the text is one line, so a taller box here
    // means it really wrapped rather than being clipped or scaled down.
    expect(
      rendered.size.height,
      greaterThan(rendered.getMaxIntrinsicHeight(double.infinity)),
    );
  });
}
