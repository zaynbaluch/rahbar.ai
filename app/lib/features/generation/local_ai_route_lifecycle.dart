import 'package:flutter/widgets.dart';

/// Tracks one long-running route operation and makes route cleanup idempotent.
///
/// Screens use an operation token before mutating UI state. Starting route
/// cleanup invalidates every outstanding token, so late native callbacks cannot
/// update a screen that is closing.
class LocalAiRouteLifecycle {
  int _operation = 0;
  Future<void>? _closeFuture;

  bool get closing => _closeFuture != null;

  int beginOperation() {
    if (closing) {
      throw StateError('The local AI screen is closing.');
    }
    return ++_operation;
  }

  bool isCurrent(int token) => !closing && token == _operation;

  void cancelOperations() {
    _operation++;
  }

  Future<void> close(Future<void> Function() cleanup) {
    final active = _closeFuture;
    if (active != null) return active;

    cancelOperations();
    final future = Future<void>.sync(cleanup);
    _closeFuture = future;
    return future;
  }
}

/// Waits for [close] to finish and then releases the route.
///
/// A failed cleanup is reported rather than swallowed, but it never blocks the
/// pop: the teacher must not be trapped on a screen that is closing.
Future<void> finishLocalAiRouteClose(
  Future<void> close, {
  required String description,
  required bool Function() isMounted,
  required VoidCallback allowPop,
  required VoidCallback pop,
}) async {
  try {
    await close;
  } catch (error, stackTrace) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'bayaz_ai',
      context: ErrorDescription(description),
    ));
  }
  if (!isMounted()) return;
  allowPop();
  // The pop must wait for the frame that republishes `canPop: true`, otherwise
  // `PopScope` intercepts it again and the route never closes.
  await WidgetsBinding.instance.endOfFrame;
  if (isMounted()) pop();
}
