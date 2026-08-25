import 'dart:async';

class LocalEmbeddingException implements Exception {
  const LocalEmbeddingException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Applies a hard wait limit and resets the native session after any failed
/// embedding request. A Dart timeout does not cancel its source future, so the
/// reset callback must release the session before another request is allowed.
class EmbeddingRequestRunner {
  const EmbeddingRequestRunner({
    this.timeout = const Duration(seconds: 30),
  });

  final Duration timeout;

  Future<List<double>> run({
    required Future<List<double>> Function() request,
    required Future<void> Function() reset,
  }) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException catch (error) {
      await _resetQuietly(reset);
      throw LocalEmbeddingException(
        'Curriculum search took too long. The local retrieval model was reset; try again.',
        error,
      );
    } catch (error) {
      await _resetQuietly(reset);
      throw LocalEmbeddingException(
        'Curriculum search failed. The local retrieval model was reset; try again.',
        error,
      );
    }
  }

  static Future<void> _resetQuietly(Future<void> Function() reset) async {
    try {
      await reset();
    } catch (_) {
      // Preserve the request failure. A later init will retry a full cleanup.
    }
  }
}
