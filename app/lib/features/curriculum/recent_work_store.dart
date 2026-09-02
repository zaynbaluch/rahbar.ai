class RecentWorkReference {
  const RecentWorkReference({required this.type, required this.id});
  final String type;
  final String id;
}

class RecentWorkStore {
  RecentWorkReference? _current;

  RecentWorkReference? get current => _current;

  void update(RecentWorkReference reference) {
    _current = reference;
  }

  void clear() {
    _current = null;
  }
}
