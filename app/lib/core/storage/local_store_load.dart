/// Result of reading a local file-backed collection.
class LocalStoreLoad<T> {
  const LocalStoreLoad({
    required this.items,
    this.recoveredFiles = 0,
  });

  final List<T> items;
  final int recoveredFiles;

  bool get recoveredCorruptData => recoveredFiles > 0;
}
