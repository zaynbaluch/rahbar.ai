import 'package:flutter_test/flutter_test.dart';

import 'package:rahbar_ai/main.dart';

void main() {
  testWidgets('app shell exposes only the existing teacher workflows',
      (WidgetTester tester) async {
    await tester.pumpWidget(const RahbarApp());

    expect(find.text('Rahbar AI'), findsOneWidget);
    expect(find.text('Offline teacher toolkit'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);

    // The content pack loads asynchronously. A second pump lets a platform error
    // be caught by the screen in environments without path_provider plugins.
    await tester.pump();
  });
}
