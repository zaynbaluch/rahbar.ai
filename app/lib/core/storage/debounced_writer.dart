import 'dart:async';

/// Coalesces rapid updates and keeps every published write in call order.
class DebouncedWriter<T> {
  DebouncedWriter({
    required Future<void> Function(T value) save,
    this.delay = const Duration(milliseconds: 300),
  }) : _save = save;

  final Future<void> Function(T value) _save;
  final Duration delay;

  Timer? _timer;
  Future<void> _tail = Future<void>.value();
  T? _latest;
  bool _hasLatest = false;

  void schedule(T value) {
    _latest = value;
    _hasLatest = true;
    _timer?.cancel();
    _timer = Timer(delay, () {
      final pending = _latest as T;
      _hasLatest = false;
      _latest = null;
      _enqueue(pending);
    });
  }

  Future<void> flush(T value) async {
    _timer?.cancel();
    _timer = null;
    _hasLatest = false;
    _latest = null;
    _enqueue(value);
    await _tail;
  }

  void _enqueue(T value) {
    _tail = _tail.catchError((_) {}).then((_) => _save(value));
  }

  Future<void> settle() async {
    if (_hasLatest) {
      final pending = _latest as T;
      _timer?.cancel();
      _timer = null;
      _hasLatest = false;
      _latest = null;
      _enqueue(pending);
    }
    await _tail;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
