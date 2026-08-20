import 'package:flutter_gemma/flutter_gemma.dart';

/// A candidate on-device model for the Week-1 generation spike.
///
/// IMPORTANT (see docs/decisions/ADR-002 & ADR-003): on an **x86_64 Android
/// emulator**, only MediaPipe `.task` text inference runs — `.litertlm` and
/// LiteRT embeddings are `arm64-v8a` only. All models below are therefore
/// `.task` (MediaPipe) and **ungated** (`needsAuth: false`) so the spike needs
/// no HuggingFace token. The real target model (Gemma 3n E2B) is gated and its
/// `.litertlm` build is arm64-only, so its true latency/quality must be
/// measured on a physical arm64 device — deferred, by design.
class SpikeModel {
  const SpikeModel({
    required this.id,
    required this.displayName,
    required this.url,
    required this.sizeLabel,
    required this.modelType,
    required this.note,
  });

  final String id;
  final String displayName;
  final String url;
  final String sizeLabel;
  final ModelType modelType;
  final String note;

  /// The MediaPipe `.task` filename (last path segment of [url]).
  String get filename => url.split('/').last;
}

/// Curated, ungated `.task` models runnable on the x86_64 emulator, smallest
/// first. Start with SmolLM to prove the pipeline instantly, then step up.
const List<SpikeModel> kSpikeModels = [
  SpikeModel(
    id: 'smollm-135m',
    displayName: 'SmolLM 135M Instruct',
    url:
        'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
    sizeLabel: '135 MB',
    modelType: ModelType.general,
    note: 'Tiny — smoke-tests the pipeline. Quality is low; English only.',
  ),
  SpikeModel(
    id: 'qwen25-0_5b',
    displayName: 'Qwen 2.5 0.5B Instruct',
    url:
        'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    sizeLabel: '0.5 GB',
    modelType: ModelType.qwen,
    note: 'First genuinely coherent tier; fits comfortably in the 3 GB emulator.',
  ),
  SpikeModel(
    id: 'qwen25-1_5b',
    displayName: 'Qwen 2.5 1.5B Instruct',
    url:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    sizeLabel: '1.6 GB',
    modelType: ModelType.qwen,
    note: 'Closer to target quality; watch emulator RAM headroom.',
  ),
  SpikeModel(
    id: 'deepseek-r1-1_5b',
    displayName: 'DeepSeek R1 Distill Qwen 1.5B',
    url:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/deepseek_q8_ekv1280.task',
    sizeLabel: '1.7 GB',
    modelType: ModelType.deepSeek,
    note: 'Reasoning-tuned; has a thinking phase.',
  ),
];
