import 'package:bayaz_ai/core/storage/local_store_load.dart';
import 'package:bayaz_ai/features/library/library_screen.dart';
import 'package:bayaz_ai/features/library/library_store.dart';
import 'package:bayaz_ai/features/library/saved_test.dart';
import 'package:bayaz_ai/features/omr/gradebook_store.dart';
import 'package:bayaz_ai/features/omr/graded_result.dart';
import 'package:bayaz_ai/features/omr/results_overview_screen.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_gate.dart';
import 'package:bayaz_ai/features/onboarding/onboarding_store.dart';
import 'package:bayaz_ai/features/resources/offline_ai_gate.dart';
import 'package:bayaz_ai/features/resources/offline_ai_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// These screens keep a `Future` in state and used to rebuild it with
/// `setState(() => _future = load())`. That closure returns the future, which
/// trips a `setState` assertion, so every refresh path is checked here for an
/// exception the widget tree would otherwise swallow.
class _FailingReadStore extends OnboardingStore {
  var fail = true;
  var reads = 0;

  @override
  Future<OnboardingState> read() async {
    reads++;
    if (fail) throw StateError('storage unavailable');
    return const OnboardingState(completed: true);
  }
}

class _StubOnboardingStore extends OnboardingStore {
  OnboardingState state = const OnboardingState();

  @override
  Future<OnboardingState> read() async => state;

  @override
  Future<void> save(OnboardingState next) async => state = next;
}

class _StubLibraryStore extends LibraryStore {
  _StubLibraryStore(this.items);

  final List<SavedTest> items;
  var loads = 0;

  @override
  Future<LocalStoreLoad<SavedTest>> load() async {
    loads++;
    return LocalStoreLoad(items: items);
  }
}

class _StubGradebookStore extends GradebookStore {
  _StubGradebookStore(this.items);

  final List<GradedResult> items;
  var loads = 0;

  @override
  Future<LocalStoreLoad<GradedResult>> loadAll() async {
    loads++;
    return LocalStoreLoad(items: items);
  }
}

void main() {
  testWidgets('retrying a failed setup read does not trip setState', (
    tester,
  ) async {
    final store = _FailingReadStore();
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingGate(
          store: store,
          inspectAi: () async => null,
          child: const Text('App'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    store.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.reads, 2);
    expect(find.text('App'), findsOneWidget);
  });

  testWidgets('completing setup refreshes the gate without tripping setState', (
    tester,
  ) async {
    final store = _StubOnboardingStore();
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingGate(
          store: store,
          inspectAi: () async => null,
          child: const Text('App'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Ayesha Khan');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.state.completed, isTrue);
    expect(find.text('App'), findsOneWidget);
  });

  testWidgets('retrying an offline AI read does not trip setState', (
    tester,
  ) async {
    var fail = true;
    final policy = OfflineAiPolicy(
      readState: () async {
        if (fail) throw StateError('setup unreadable');
        return const OnboardingState(offlineAiEnabled: true);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineAiGate(
          title: 'Generate',
          policy: policy,
          enabledBuilder: (_) => const Text('Generator'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not read the offline AI setting.'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Generator'), findsOneWidget);
  });

  testWidgets('returning from settings re-reads the offline AI switch', (
    tester,
  ) async {
    var enabled = false;
    final policy = OfflineAiPolicy(
      readState: () async => OnboardingState(offlineAiEnabled: enabled),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineAiGate(
          title: 'Generate',
          policy: policy,
          // The real settings screen reads a file-backed store that never
          // resolves under the test binding, so a stand-in route is pushed.
          openSettings: (context) => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Setup')),
                body: const SizedBox.shrink(),
              ),
            ),
          ),
          enabledBuilder: (_) => const Text('Generator'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline AI is turned off'), findsOneWidget);

    enabled = true;
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(find.text('Setup'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Generator'), findsOneWidget);
  });

  testWidgets('pulling to refresh the library does not trip setState', (
    tester,
  ) async {
    final store = _StubLibraryStore([
      SavedTest(
        id: 'test-1',
        kind: 'mcq',
        topic: 'Photosynthesis',
        createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(home: LibraryScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(store.loads, 1);

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.loads, 2);
  });

  testWidgets('pulling to refresh saved results does not trip setState', (
    tester,
  ) async {
    final store = _StubGradebookStore([
      const GradedResult(
        id: 'result-1',
        testId: 'test-1',
        testTopic: 'Photosynthesis',
        studentName: 'Ayesha Khan',
        correct: 1,
        total: 1,
        marks: 'A',
        correctAnswers: 'A',
        createdAtMillis: 1,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: ResultsOverviewScreen(store: store)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(store.loads, 1);

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.loads, 2);
  });
}
