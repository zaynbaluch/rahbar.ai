import 'dart:convert';

import 'package:bayaz_ai/features/resources/resource_manifest.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a checksum-protected HTTPS model', () {
    final manifest = ResourceManifest.fromJson({
      'schema_version': 1,
      'generated_at_utc': '2026-07-19T00:00:00Z',
      'resources': [
        {
          'id': 'model.example',
          'kind': 'language_model',
          'version': '1.0.0',
          'display_name': 'Example',
          'file_name': 'model.gguf',
          'size_bytes': 123,
          'sha256': List.filled(64, 'a').join(),
          'download_url': 'https://models.example.pk/model.gguf',
          'required': false,
          'license_name': 'Example license',
          'license_url': 'https://models.example.pk/license',
        },
      ],
    });

    expect(manifest.resources.single.kind, ResourceKind.languageModel);
    expect(manifest.resources.single.isDownloadable, isTrue);
  });

  test('rejects path traversal in resource filenames', () {
    expect(
      () => ResourceManifest.fromJson({
        'schema_version': 1,
        'generated_at_utc': '2026-07-19T00:00:00Z',
        'resources': [
          {
            'id': 'model.example',
            'kind': 'language_model',
            'version': '1.0.0',
            'file_name': '../model.gguf',
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('rejects downloads without a valid checksum', () {
    expect(
      () => ResourceManifest.fromJson({
        'schema_version': 1,
        'generated_at_utc': '2026-07-19T00:00:00Z',
        'resources': [
          {
            'id': 'model.example',
            'kind': 'language_model',
            'version': '1.0.0',
            'file_name': 'model.gguf',
            'download_url': 'https://models.example.pk/model.gguf',
          },
        ],
      }),
      throwsFormatException,
    );
  });

  testWidgets('production models use pinned verified downloads', (tester) async {
    final raw = await rootBundle.loadString('assets/config/runtime_manifest.json');
    final manifest = ResourceManifest.fromJson(
      Map<String, Object?>.from(jsonDecode(raw) as Map),
    );
    final models = manifest.resources
        .where((resource) => resource.kind != ResourceKind.curriculumModule)
        .toList(growable: false);

    expect(models, hasLength(2));
    for (final model in models) {
      expect(model.isDownloadable, isTrue);
      expect(model.downloadUrl!.host, 'huggingface.co');
      expect(model.downloadUrl!.pathSegments, contains('resolve'));
      expect(model.sizeBytes, greaterThan(0));
      expect(model.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    }

    final embedding = models.singleWhere(
      (resource) => resource.kind == ResourceKind.embeddingModel,
    );
    expect(embedding.fileName, 'bge-small-en-v1.5-f16.gguf');
    expect(embedding.sizeBytes, 67582560);
    expect(
      embedding.sha256,
      'c5d2302edc429f679642433b9f96dd217799727a06e675abef3b40a79f5e1589',
    );

    final language = models.singleWhere(
      (resource) => resource.kind == ResourceKind.languageModel,
    );
    expect(language.fileName, 'LFM2-1.2B-Q4_K_M.gguf');
    expect(language.sizeBytes, 730893024);
    expect(
      language.sha256,
      'ac63aeef935e5a4ca147ad6d966487bb0c23220ea20a5f49ad315614392f104e',
    );
  });
}
