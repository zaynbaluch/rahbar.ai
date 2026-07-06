import 'package:flutter_gemma/flutter_gemma.dart';

/// A candidate on-device model for the generation spike.
///
/// See docs/decisions/ADR-002 & ADR-003. `.task` (MediaPipe) models run on the
/// x86_64 emulator and arm64; `.litertlm` (LiteRT-LM) models are **arm64-only**
/// but GPU-capable — the path for the mobile-optimized Gemma candidate.
enum ModelFormat { task, litertlm }

class SpikeModel {
  const SpikeModel({
    required this.id,
    required this.displayName,
    required this.sizeLabel,
    required this.modelType,
    required this.format,
    required this.note,
    this.url,
    this.localFile,
    this.defaultBackend = PreferredBackend.cpu,
  });

  final String id;
  final String displayName;
  final String sizeLabel;
  final ModelType modelType;
  final ModelFormat format;
  final String note;

  /// Network source (downloaded on-device). Null if [localFile] is used.
  final String? url;

  /// Filename in the app's external files dir (pushed via USB to avoid a slow
  /// on-device download). Resolved against getExternalStorageDirectory().
  final String? localFile;

  /// GPU generally only usable for `.litertlm` on a real arm64 device.
  final PreferredBackend defaultBackend;

  /// Model id flutter_gemma tracks it by (its filename).
  String get filename => localFile ?? (url ?? '').split('/').last;
}

/// The lead candidate this session: mobile-optimized Gemma, ungated, loaded from
/// a USB-pushed local file, run on the GPU via LiteRT.
const List<SpikeModel> kSpikeModels = [
  SpikeModel(
    id: 'gemma-4-e2b',
    displayName: 'Gemma 4 E2B (LiteRT)',
    sizeLabel: '2.6 GB',
    modelType: ModelType.gemma4,
    format: ModelFormat.litertlm,
    localFile: 'gemma-4-e2b.litertlm',
    defaultBackend: PreferredBackend.gpu,
    note: 'Mobile-optimized, ungated. LiteRT can run it <~1.5GB and use the GPU.',
  ),
  // MediaPipe `.task` fallbacks (also run on emulator). Ungated.
  SpikeModel(
    id: 'qwen25-1_5b',
    displayName: 'Qwen 2.5 1.5B (MediaPipe)',
    sizeLabel: '1.6 GB',
    modelType: ModelType.qwen,
    format: ModelFormat.task,
    url:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    note: 'CPU-only .task path; comparison point.',
  ),
  SpikeModel(
    id: 'smollm-135m',
    displayName: 'SmolLM 135M (MediaPipe)',
    sizeLabel: '135 MB',
    modelType: ModelType.general,
    format: ModelFormat.task,
    url:
        'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
    note: 'Tiny smoke-test model.',
  ),
];
