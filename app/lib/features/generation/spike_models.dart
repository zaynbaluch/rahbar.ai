import 'package:flutter_gemma/flutter_gemma.dart';

/// A candidate on-device model for the generation spike.
///
/// See docs/decisions/ADR-002 & ADR-003. `.task` (MediaPipe) models run on the
/// x86_64 emulator and arm64; `.litertlm` (LiteRT-LM) models are **arm64-only**
/// but GPU-capable — the path for the mobile-optimized Gemma candidate.
enum ModelFormat { task, litertlm, gguf }

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
  // SHIPPING model: LFM2 1.2B via llama.cpp. Speed bake-off (ADR-003) picked it
  // over Qwen3 1.7B — ~2× decode / ~1.4× prefill on CPU — with MCQ schema
  // guaranteed by grammar-constrained decoding (mcq_grammar.dart). ChatML template
  // (LFM2 uses the same <|im_start|> structure), greedy.
  SpikeModel(
    id: 'lfm2-1.2b-gguf',
    displayName: 'LFM2 1.2B (llama.cpp)',
    sizeLabel: '0.7 GB',
    modelType: ModelType.general,
    format: ModelFormat.gguf,
    localFile: 'lfm2-1.2b.gguf',
    note: 'Q4_K_M GGUF via llama.cpp, ChatML + greedy + GBNF grammar. ~2× Qwen3 decode.',
  ),
  // Prior shipping model, kept as a quality-fallback candidate: Qwen3 1.7B.
  // Best schema discipline unaided (10/10) but ~half the decode speed of LFM2.
  SpikeModel(
    id: 'qwen3-1.7b-gguf',
    displayName: 'Qwen3 1.7B (llama.cpp)',
    sizeLabel: '1.1 GB',
    modelType: ModelType.qwen,
    format: ModelFormat.gguf,
    localFile: 'qwen3-1.7b.gguf',
    note: 'Q4 GGUF via llama.cpp, ChatML + greedy. Strong grounded quality (~3.3 tok/s CPU).',
  ),
  // Low-RAM fallback: Llama 3.2 1B (fastest/lightest, but ~5/10 keys — see ADR-003).
  SpikeModel(
    id: 'llama-3.2-1b-gguf',
    displayName: 'Llama 3.2 1B (llama.cpp)',
    sizeLabel: '0.8 GB',
    modelType: ModelType.general,
    format: ModelFormat.gguf,
    localFile: 'llama-3.2-1b.gguf',
    note: 'Q4 GGUF via llama.cpp. Fastest (~7.5 tok/s) but weaker answer-key accuracy.',
  ),
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
