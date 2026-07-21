/// Runs retrieval and generation as separate native model sessions.
///
/// The pinned binding uses process-wide native state, and budget devices cannot
/// safely retain both model allocations. Release the generator before retrieval
/// and always release the retriever before loading the generator again.
class LocalModelHandoff {
  const LocalModelHandoff();

  Future<T> retrieve<T>({
    required Future<void> Function() releaseGenerator,
    required Future<T> Function() runRetrieval,
    required Future<void> Function() releaseRetriever,
  }) async {
    await releaseGenerator();
    try {
      return await runRetrieval();
    } finally {
      await releaseRetriever();
    }
  }
}
