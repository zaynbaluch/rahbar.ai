import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

const int kResourceManifestSchemaVersion = 1;

enum ResourceKind { curriculumModule, embeddingModel, languageModel }

ResourceKind _kindFromWire(String value) => switch (value) {
      'curriculum_module' => ResourceKind.curriculumModule,
      'embedding_model' => ResourceKind.embeddingModel,
      'language_model' => ResourceKind.languageModel,
      _ => throw FormatException('Unsupported resource kind: $value'),
    };

String resourceKindWireName(ResourceKind kind) => switch (kind) {
      ResourceKind.curriculumModule => 'curriculum_module',
      ResourceKind.embeddingModel => 'embedding_model',
      ResourceKind.languageModel => 'language_model',
    };

class ResourceDescriptor {
  const ResourceDescriptor({
    required this.id,
    required this.kind,
    required this.version,
    required this.displayName,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.required,
    required this.licenseName,
    required this.licenseUrl,
    this.downloadUrl,
    this.bundledAsset,
    this.classCode,
    this.subjectCode,
  });

  final String id;
  final ResourceKind kind;
  final String version;
  final String displayName;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final bool required;
  final String licenseName;
  final String licenseUrl;
  final Uri? downloadUrl;
  final String? bundledAsset;
  final String? classCode;
  final String? subjectCode;

  bool get isBundled => bundledAsset != null && bundledAsset!.isNotEmpty;
  bool get isDownloadable => downloadUrl != null;

  factory ResourceDescriptor.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    final version = (json['version'] as String? ?? '').trim();
    final fileName = (json['file_name'] as String? ?? '').trim();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,119}$').hasMatch(id)) {
      throw FormatException('Invalid resource id: $id');
    }
    if (!RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_-]{0,39}$').hasMatch(version)) {
      throw FormatException('Invalid resource version for $id: $version');
    }
    if (fileName.isEmpty || fileName.contains('/') || fileName.contains('\\')) {
      throw FormatException('Resource file_name must be a plain file name: $fileName');
    }

    final urlText = (json['download_url'] as String? ?? '').trim();
    final downloadUrl = urlText.isEmpty ? null : Uri.parse(urlText);
    if (downloadUrl != null &&
        (downloadUrl.scheme != 'https' || downloadUrl.host.isEmpty)) {
      throw FormatException('Resource downloads must use HTTPS: $downloadUrl');
    }

    final bundled = (json['bundled_asset'] as String? ?? '').trim();
    final sizeBytes = (json['size_bytes'] as num?)?.toInt() ?? 0;
    final sha256 = (json['sha256'] as String? ?? '').trim().toLowerCase();
    if (downloadUrl != null) {
      if (sizeBytes <= 0) {
        throw FormatException('Downloadable resource $id requires an exact size.');
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
        throw FormatException('Downloadable resource $id requires a SHA-256 checksum.');
      }
    }

    return ResourceDescriptor(
      id: id,
      kind: _kindFromWire(json['kind'] as String? ?? ''),
      version: version,
      displayName: (json['display_name'] as String? ?? id).trim(),
      fileName: fileName,
      sizeBytes: sizeBytes,
      sha256: sha256,
      required: json['required'] as bool? ?? false,
      licenseName: (json['license_name'] as String? ?? '').trim(),
      licenseUrl: (json['license_url'] as String? ?? '').trim(),
      downloadUrl: downloadUrl,
      bundledAsset: bundled.isEmpty ? null : bundled,
      classCode: json['class_code'] as String?,
      subjectCode: json['subject_code'] as String?,
    );
  }
}

class ResourceManifest {
  const ResourceManifest({
    required this.schemaVersion,
    required this.generatedAtUtc,
    required this.resources,
  });

  final int schemaVersion;
  final DateTime? generatedAtUtc;
  final List<ResourceDescriptor> resources;

  factory ResourceManifest.fromJson(Map<String, Object?> json) {
    final schema = json['schema_version'] as int? ?? 0;
    if (schema != kResourceManifestSchemaVersion) {
      throw FormatException('Unsupported manifest schema: $schema');
    }
    final resources = (json['resources'] as List? ?? const [])
        .map((item) => ResourceDescriptor.fromJson(
              Map<String, Object?>.from(item as Map),
            ))
        .toList(growable: false);
    final ids = <String>{};
    for (final resource in resources) {
      if (!ids.add(resource.id)) {
        throw FormatException('Duplicate resource id: ${resource.id}');
      }
    }
    final generated = (json['generated_at_utc'] as String? ?? '').trim();
    return ResourceManifest(
      schemaVersion: schema,
      generatedAtUtc: generated.isEmpty ? null : DateTime.parse(generated).toUtc(),
      resources: resources,
    );
  }

  static Future<ResourceManifest> loadBundled() async {
    final raw = await rootBundle.loadString('assets/config/runtime_manifest.json');
    return ResourceManifest.fromJson(
      Map<String, Object?>.from(jsonDecode(raw) as Map),
    );
  }
}
