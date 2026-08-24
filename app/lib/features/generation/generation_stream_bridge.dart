import 'dart:async';

class ModelCompletion {
  const ModelCompletion({
    required this.promptId,
    required this.success,
    this.errorDetails,
  });

  final String promptId;
  final bool success;
  final String? errorDetails;
}

class LocalGenerationException implements Exception {
  const LocalGenerationException([this.details]);

  final String? details;

  @override
  String toString() {
    final message = details?.trim();
    if (message == null || message.isEmpty) {
      return 'Offline generation failed before it completed.';
    }
    return 'Offline generation failed: $message';
  }
}

/// Connects the binding's separate token and completion streams into one stream
/// that closes only after the matching prompt succeeds and surfaces native
/// completion failures to callers.
class GenerationStreamBridge {
  const GenerationStreamBridge();

  Stream<String> run({
    required Stream<String> tokens,
    required Stream<ModelCompletion> completions,
    required Future<String> Function() start,
    required Future<void> Function() stop,
  }) {
    late final StreamController<String> output;
    StreamSubscription<String>? tokenSubscription;
    StreamSubscription<ModelCompletion>? completionSubscription;
    final earlyCompletions = <ModelCompletion>[];
    String? promptId;
    var finished = false;

    Future<void> cancelInputs() async {
      await tokenSubscription?.cancel();
      await completionSubscription?.cancel();
    }

    Future<void> finish({Object? error, StackTrace? stackTrace}) async {
      if (finished) return;
      finished = true;
      if (error != null && !output.isClosed) {
        output.addError(error, stackTrace);
      }
      await cancelInputs();
      if (!output.isClosed) await output.close();
    }

    void handleCompletion(ModelCompletion completion) {
      if (finished) return;
      final activeId = promptId;
      if (activeId == null) {
        earlyCompletions.add(completion);
        return;
      }
      if (completion.promptId != activeId) return;
      if (completion.success) {
        unawaited(finish());
      } else {
        unawaited(finish(
          error: LocalGenerationException(completion.errorDetails),
        ));
      }
    }

    output = StreamController<String>(
      onListen: () {
        tokenSubscription = tokens.listen(
          (token) {
            if (!finished && !output.isClosed) output.add(token);
          },
          onError: (Object error, StackTrace stackTrace) {
            unawaited(finish(error: error, stackTrace: stackTrace));
          },
        );
        completionSubscription = completions.listen(
          handleCompletion,
          onError: (Object error, StackTrace stackTrace) {
            unawaited(finish(error: error, stackTrace: stackTrace));
          },
        );
        unawaited(() async {
          try {
            promptId = await start();
            final pending = List<ModelCompletion>.from(earlyCompletions);
            earlyCompletions.clear();
            for (final completion in pending) {
              handleCompletion(completion);
              if (finished) break;
            }
          } catch (error, stackTrace) {
            await finish(error: error, stackTrace: stackTrace);
          }
        }());
      },
      onCancel: () async {
        if (!finished) {
          try {
            await stop();
          } catch (_) {
            // Cancellation should still release stream subscriptions even when
            // the native stop operation reports an error.
          }
        }
        finished = true;
        await cancelInputs();
      },
    );
    return output.stream;
  }
}
