import 'package:bayaz_ai/features/resources/resource_manifest.dart';
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
}
