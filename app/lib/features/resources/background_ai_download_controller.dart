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

/// App-scoped source of truth for Offline AI installation state.
///
/// Automatic setup, Settings, and any route that opens Offline AI management use
/// the same controller so the app cannot offer a second download while one is
/// already running elsewhere.
class BackgroundAiDownloadController {
  BackgroundAiDownloadController({
    LocalAiResources? resources,
    bool? autoDownloadEnabled,
  }) : _resources = resources ?? LocalAiResources(),
       autoDownloadEnabled = autoDownloadEnabled ?? !autoDownloadDisabled;

  static final BackgroundAiDownloadController shared =
      BackgroundAiDownloadController();

  static const bool autoDownloadDisabled = bool.fromEnvironment(
    'BAYAZ_DISABLE_AUTO_AI_DOWNLOAD',
    defaultValue: false,
  );

  final LocalAiResources _resources;
  final bool autoDownloadEnabled;
  final _updates = StreamController<BackgroundAiDownloadState>.broadcast();
  BackgroundAiDownloadState _state = const BackgroundAiDownloadState();
  DownloadCancellationToken? _cancellationToken;
  Future<void>? _activeOperation;

  Stream<BackgroundAiDownloadState> get stream => _updates.stream;
  BackgroundAiDownloadState get state => _state;

  /// Starts the automatic setup policy. The developer switch suppresses only
  /// this automatic action; an explicit teacher download remains available.
  Future<void> startIfNeeded() async {
    if (!autoDownloadEnabled || await _resources.isAutoDownloadSuppressed()) {
      await refresh();
      return;
    }
    await _joinDownloadMissing();
  }

  /// Re-inspects the managed files without starting a download.
  Future<void> refresh() async {
    if (_state.running) return;
    try {
      final available = await _resources.inspect();
      _set(
        BackgroundAiDownloadState(
          progress: available.fullyConfigured ? 1 : null,
          completed: available.fullyConfigured,
        ),
      );
    } catch (e) {
      _set(BackgroundAiDownloadState(error: e.toString()));
    }
  }

  /// Downloads every missing Offline AI resource. Concurrent callers join the
  /// same operation instead of launching competing downloads.
  Future<void> downloadMissing() async {
    await _joinDownloadMissing();
    if (_state.completed) {
      await _resources.setAutoDownloadSuppressed(false);
    }
  }

  Future<void> markDownloadsRemovedByUser() async {
    await _resources.setAutoDownloadSuppressed(true);
    await refresh();
  }

  Future<void> _joinDownloadMissing() {
    final active = _activeOperation;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _downloadMissing().whenComplete(() {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    });
    _activeOperation = operation;
    return operation;
  }

  Future<void> _downloadMissing() async {
    try {
      final available = await _resources.inspect();
      if (available.fullyConfigured) {
        _set(const BackgroundAiDownloadState(progress: 1, completed: true));
        return;
      }

      final missingEmbedding = !available.embeddingModel.installed;
      final missingLanguage = !available.languageModel.installed;
      final totalSteps = (missingEmbedding ? 1 : 0) + (missingLanguage ? 1 : 0);
      var completedSteps = 0;
      final token = DownloadCancellationToken();
      _cancellationToken = token;
      _set(const BackgroundAiDownloadState(running: true));

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
        await _resources.installEmbeddingModel(
          cancellationToken: token,
          onProgress: updateProgress,
        );
        completedSteps++;
        _set(
          BackgroundAiDownloadState(
            running: true,
            progress: totalSteps == 0 ? null : completedSteps / totalSteps,
          ),
        );
      }
      if (missingLanguage) {
        await _resources.installLanguageModel(
          cancellationToken: token,
          onProgress: updateProgress,
        );
        completedSteps++;
      }
      _set(const BackgroundAiDownloadState(progress: 1, completed: true));
    } on DownloadCancelled {
      _set(const BackgroundAiDownloadState());
    } catch (e) {
      _set(BackgroundAiDownloadState(error: e.toString()));
    } finally {
      _cancellationToken = null;
    }
  }

  void cancel() => _cancellationToken?.cancel();

  Future<void> retry() async {
    _set(const BackgroundAiDownloadState());
    await downloadMissing();
  }

  void _set(BackgroundAiDownloadState value) {
    _state = value;
    if (!_updates.isClosed) _updates.add(value);
  }

  void dispose() {
    _cancellationToken?.cancel();
    _updates.close();
    _resources.dispose();
  }
}
