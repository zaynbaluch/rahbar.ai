import 'dart:async';

import 'download_manager.dart';
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

  bool get needsAttention => error != null;
}

/// Owns automatic offline-AI setup independently from individual screens.
class BackgroundAiDownloadController {
  BackgroundAiDownloadController({
    LocalAiResources? resources,
    bool? autoDownloadEnabled,
  }) : _resources = resources ?? LocalAiResources(),
       autoDownloadEnabled = autoDownloadEnabled ?? !autoDownloadDisabled;

  static const bool autoDownloadDisabled = bool.fromEnvironment(
    'BAYAZ_DISABLE_AUTO_AI_DOWNLOAD',
    defaultValue: false,
  );

  final LocalAiResources _resources;
  final bool autoDownloadEnabled;
  final _updates = StreamController<BackgroundAiDownloadState>.broadcast();
  BackgroundAiDownloadState _state = const BackgroundAiDownloadState();

  Stream<BackgroundAiDownloadState> get stream => _updates.stream;
  BackgroundAiDownloadState get state => _state;

  Future<void> startIfNeeded() async {
    if (!autoDownloadEnabled || _state.running || _state.completed) return;
    try {
      final available = await _resources.inspect();
      if (available.fullyConfigured) {
        _set(const BackgroundAiDownloadState(completed: true));
        return;
      }

      final missingEmbedding = !available.embeddingModel.installed;
      final missingLanguage = !available.languageModel.installed;
      final totalSteps = (missingEmbedding ? 1 : 0) + (missingLanguage ? 1 : 0);
      var completedSteps = 0;
      _set(const BackgroundAiDownloadState(running: true, progress: 0));

      void updateProgress(DownloadProgress progress) {
        final local = progress.fraction;
        if (local == null || totalSteps == 0) {
          _set(const BackgroundAiDownloadState(running: true));
          return;
        }
        _set(
          BackgroundAiDownloadState(
            running: true,
            progress: ((completedSteps + local) / totalSteps).clamp(0.0, 1.0),
          ),
        );
      }

      if (missingEmbedding) {
        await _resources.installEmbeddingModel(onProgress: updateProgress);
        completedSteps++;
        _set(
          BackgroundAiDownloadState(
            running: true,
            progress: totalSteps == 0 ? null : completedSteps / totalSteps,
          ),
        );
      }
      if (missingLanguage) {
        await _resources.installLanguageModel(onProgress: updateProgress);
        completedSteps++;
      }
      _set(const BackgroundAiDownloadState(progress: 1, completed: true));
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
    if (!_updates.isClosed) _updates.add(value);
  }

  void dispose() {
    _updates.close();
    _resources.dispose();
  }
}
