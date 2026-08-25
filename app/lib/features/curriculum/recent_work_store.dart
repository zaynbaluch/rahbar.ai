import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/atomic_file_store.dart';

class RecentWorkReference {
  const RecentWorkReference({required this.type, required this.id});
  final String type;
  final String id;

  Map<String, Object?> toJson() => {'type': type, 'id': id};

  factory RecentWorkReference.fromJson(Map<String, dynamic> json) =>
      RecentWorkReference(
        type: json['type'] as String? ?? '',
        id: json['id'] as String? ?? '',
      );
}

class _RecentState {
  const _RecentState({this.reference, this.activeGradingTestId});
  final RecentWorkReference? reference;
  final String? activeGradingTestId;

  Map<String, Object?> toJson() => {
    if (reference != null) ...reference!.toJson(),
    if (activeGradingTestId != null) 'activeGradingTestId': activeGradingTestId,
  };
}

class RecentWorkStore {
  RecentWorkStore({Future<File> Function()? fileProvider})
    : _fileProvider = fileProvider ?? _defaultFile;

  final Future<File> Function() _fileProvider;

  static Future<File> _defaultFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'preferences', 'recent_work.v1.json'));
  }

  Future<_RecentState> _readState() async {
    final file = await _fileProvider();
    if (!await file.exists()) return const _RecentState();
    try {
      final json = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      final type = json['type'] as String? ?? '';
      final id = json['id'] as String? ?? '';
      return _RecentState(
        reference: type.isEmpty || id.isEmpty
            ? null
            : RecentWorkReference(type: type, id: id),
        activeGradingTestId: json['activeGradingTestId'] as String?,
      );
    } catch (_) {
      await AtomicFileStore.shared.quarantineCorrupt(file);
      return const _RecentState();
    }
  }

  Future<void> _write(_RecentState state) async {
    final file = await _fileProvider();
    if (state.reference == null && state.activeGradingTestId == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    await AtomicFileStore.shared.writeJson(file, state.toJson());
  }

  Future<RecentWorkReference?> current() async =>
      (await _readState()).reference;

  Future<String?> activeGradingTestId() async =>
      (await _readState()).activeGradingTestId;

  Future<void> update(RecentWorkReference reference) async {
    final state = await _readState();
    await _write(
      _RecentState(
        reference: reference,
        activeGradingTestId: state.activeGradingTestId,
      ),
    );
  }

  Future<void> clearRecent() async {
    final state = await _readState();
    await _write(_RecentState(activeGradingTestId: state.activeGradingTestId));
  }

  Future<void> setActiveGrading(String testId) async {
    final state = await _readState();
    await _write(
      _RecentState(reference: state.reference, activeGradingTestId: testId),
    );
  }

  Future<void> clearActiveGrading() async {
    final state = await _readState();
    await _write(_RecentState(reference: state.reference));
  }

  Future<void> invalidateTarget(String id) async {
    final state = await _readState();
    await _write(
      _RecentState(
        reference: state.reference?.id == id ? null : state.reference,
        activeGradingTestId: state.activeGradingTestId == id
            ? null
            : state.activeGradingTestId,
      ),
    );
  }

  Future<void> clear() async {
    final file = await _fileProvider();
    if (await file.exists()) await file.delete();
  }
}
