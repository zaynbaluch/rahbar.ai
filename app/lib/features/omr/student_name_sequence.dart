/// Chooses the next unused default student label for a saved paper.
class StudentNameSequence {
  static final RegExp _defaultName = RegExp(
    r'^Student\s+(\d+)$',
    caseSensitive: false,
  );

  static int nextNumber(Iterable<String> existingNames) {
    var highest = 0;
    for (final name in existingNames) {
      final match = _defaultName.firstMatch(name.trim());
      if (match == null) continue;
      final number = int.tryParse(match.group(1)!);
      if (number != null && number > highest) highest = number;
    }
    return highest + 1;
  }

  static String nextName(Iterable<String> existingNames) =>
      'Student ${nextNumber(existingNames)}';
}
