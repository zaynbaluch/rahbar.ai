import 'dart:async';

import 'local_ai_resources.dart';

class BackgroundAiDownloadState {
  const BackgroundAiDownloadState({
    this.progress,
    this.running = false,
    this.completed = false,
    this.error,
  });

  final double? progress;
  final bool running;
  final bool completed;
  final String? error;
}

/// Owns automatic AI setup independently from individual screens.
class BackgroundAiDownloadController {
  BackgroundAiDownloadController({LocalAiResources? resources})
      : _resources = resources ?? LocalAiResources();

  final LocalAiResources _resources;
  final _updates = StreamController<BackgroundAiDownloadState>.broadcast();
  BackgroundAiDownloadState _state = const BackgroundAiDownloadState();

  Stream<BackgroundAiDownloadState> get stream => _updates.stream;
  BackgroundAiDownloadState get state => _state;

  Future<void> startIfNeeded() async {
    if (_state.running || _state.completed) return;
    try {
      final available = await _resources.inspect();
      if (available.fullyConfigured) {
        _set(const BackgroundAiDownloadState(completed: true));
        return;
      }
      _set(const BackgroundAiDownloadState(running: true));
      await _resources.installEmbeddingModel(
        onProgress: (p) => _set(BackgroundAiDownloadState(
          running: true,
          progress: p.fraction,
        )),
      );
      await _resources.installLanguageModel();
      _set(const BackgroundAiDownloadState(completed: true));
    } catch (e) {
      _set(BackgroundAiDownloadState(error: e.toString()));
    }
  }

  Future<void> retry() async {
    _state = const BackgroundAiDownloadState();
    await startIfNeeded();
  }

  void _set(BackgroundAiDownloadState value) {
    _state = value;
    _updates.add(value);
  }

  void dispose() {
    _updates.close();
    _resources.dispose();
  }
}
