import 'package:bayaz_ai/design_system/components/frame_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('operation artwork uses animated WebP when motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BayazFrameAnimation(name: 'test_ready')),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as AssetImage;
    expect(provider.assetName, 'assets/ui/animations/test_ready.webp');
  });

  testWidgets(
    'operation artwork uses final source frame when motion is reduced',
    (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: BayazFrameAnimation(name: 'test_ready')),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as AssetImage;
      expect(
        provider.assetName,
        'assets/ui/animations/frames/test_ready/12.png',
      );
    },
  );
}
