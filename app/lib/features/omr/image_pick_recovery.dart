import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/atomic_file_store.dart';
import '../generation/mcq_parser.dart';
import '../curriculum/teaching_context.dart';

class PendingImagePick {
  const PendingImagePick({
    required this.test,
    required this.source,
    required this.createdAtMillis,
    this.recoveredImagePath,
    this.teachingContext,
  });

  final McqTest test;
  final String source;
  final int createdAtMillis;
  final String? recoveredImagePath;
  final TeachingContext? teachingContext;

  Map<String, Object?> toJson() => {
    'test': test.toJson(),
    'source': source,
    'created_at_millis': createdAtMillis,
    'recovered_image_path': recoveredImagePath,
    if (teachingContext != null) 'teaching_context': teachingContext!.toJson(),
  };

  factory PendingImagePick.fromJson(Map<String, dynamic> json) =>
      PendingImagePick(
        test: McqTest.fromJson(Map<String, dynamic>.from(json['test'] as Map)),
        source: json['source'] as String? ?? 'unknown',
        createdAtMillis: json['created_at_millis'] as int? ?? 0,
        recoveredImagePath: json['recovered_image_path'] as String?,
        teachingContext: json['teaching_context'] == null
            ? null
            : TeachingContext.fromJson(
                Map<String, dynamic>.from(json['teaching_context'] as Map),
              ),
      );

  PendingImagePick copyWith({String? recoveredImagePath}) => PendingImagePick(
    test: test,
    source: source,
    createdAtMillis: createdAtMillis,
    recoveredImagePath: recoveredImagePath ?? this.recoveredImagePath,
    teachingContext: teachingContext,
  );
}

class PendingImagePickStore {
  PendingImagePickStore({
    Future<File> Function()? fileProvider,
    int Function()? nowMillis,
  }) : _fileProvider = fileProvider ?? _defaultFile,
       _nowMillis = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Future<File> Function() _fileProvider;
  final int Function() _nowMillis;

  static Future<File> _defaultFile() async {
    final support = await getApplicationSupportDirectory();
    return File(
      p.join(support.path, 'preferences', 'pending_image_pick.v1.json'),
    );
  }

  Future<void> begin(
    McqTest test,
    ImageSource source, {
    TeachingContext? teachingContext,
  }) async {
    final file = await _fileProvider();
    await AtomicFileStore.shared.writeJson(
      file,
      PendingImagePick(
        test: test,
        source: source.name,
        createdAtMillis: _nowMillis(),
        teachingContext: teachingContext,
      ).toJson(),
    );
  }

  Future<PendingImagePick?> read() async {
    final file = await _fileProvider();
    if (!await file.exists()) return null;
    try {
      return PendingImagePick.fromJson(
        Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map),
      );
    } catch (_) {
      await AtomicFileStore.shared.quarantineCorrupt(file);
      return null;
    }
  }

  Future<void> save(PendingImagePick pending) async {
    final file = await _fileProvider();
    await AtomicFileStore.shared.writeJson(file, pending.toJson());
  }

  Future<void> clear({bool deleteRecoveredImage = true}) async {
    final file = await _fileProvider();
    await AtomicFileStore.shared.runExclusive(file.path, () async {
      String? recoveredPath;
      if (deleteRecoveredImage && await file.exists()) {
        try {
          final json = Map<String, dynamic>.from(
            jsonDecode(await file.readAsString()) as Map,
          );
          recoveredPath = json['recovered_image_path'] as String?;
        } catch (_) {
          // The state file is removed below even when it cannot be decoded.
        }
      }
      if (await file.exists()) await file.delete();
      if (recoveredPath != null) {
        final recovered = File(recoveredPath);
        if (await recovered.exists()) await recovered.delete();
      }
    });
  }
}

class LostImageData {
  const LostImageData({this.paths = const [], this.error});

  final List<String> paths;
  final Object? error;

  bool get isEmpty => paths.isEmpty && error == null;
}

abstract interface class LostImageDataProvider {
  Future<LostImageData> retrieve();
}

class ImagePickerLostDataProvider implements LostImageDataProvider {
  ImagePickerLostDataProvider([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<LostImageData> retrieve() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return const LostImageData();
    return LostImageData(
      paths: response.files?.map((file) => file.path).toList() ?? const [],
      error: response.exception,
    );
  }
}

class RecoveredImagePick {
  const RecoveredImagePick({
    required this.test,
    required this.imagePath,
    this.teachingContext,
  });

  final McqTest test;
  final String imagePath;
  final TeachingContext? teachingContext;
}

class ImagePickRecoveryService {
  ImagePickRecoveryService({
    PendingImagePickStore? store,
    LostImageDataProvider? lostData,
    Future<Directory> Function()? supportDirectory,
    int Function()? nowMillis,
    this.maxPendingAge = const Duration(hours: 24),
  }) : store = store ?? PendingImagePickStore(),
       _lostData = lostData ?? ImagePickerLostDataProvider(),
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _nowMillis = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch);

  final PendingImagePickStore store;
  final LostImageDataProvider _lostData;
  final Future<Directory> Function() _supportDirectory;
  final int Function() _nowMillis;
  final Duration maxPendingAge;

  Future<RecoveredImagePick?> recover() async {
    final pending = await store.read();
    final lost = await _lostData.retrieve();
    if (pending == null) return null;

    final age = _nowMillis() - pending.createdAtMillis;
    if (age < 0 || age > maxPendingAge.inMilliseconds) {
      await store.clear();
      return null;
    }

    final existingPath = pending.recoveredImagePath;
    if (existingPath != null && await File(existingPath).exists()) {
      return RecoveredImagePick(
        test: pending.test,
        imagePath: existingPath,
        teachingContext: pending.teachingContext,
      );
    }

    if (lost.error != null || lost.paths.isEmpty) {
      await store.clear();
      return null;
    }

    final source = File(lost.paths.first);
    if (!await source.exists()) {
      await store.clear();
      return null;
    }
    final support = await _supportDirectory();
    final recoveryDir = Directory(p.join(support.path, 'recovered_images'));
    await recoveryDir.create(recursive: true);
    final extension = p.extension(source.path).isEmpty
        ? '.jpg'
        : p.extension(source.path);
    final destination = File(
      p.join(recoveryDir.path, 'omr-${pending.createdAtMillis}$extension'),
    );
    await source.copy(destination.path);
    final updated = pending.copyWith(recoveredImagePath: destination.path);
    await store.save(updated);
    return RecoveredImagePick(
      test: pending.test,
      imagePath: destination.path,
      teachingContext: pending.teachingContext,
    );
  }
}
