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
