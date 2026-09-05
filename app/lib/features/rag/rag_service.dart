import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../curriculum/curriculum_module_registry.dart';
import '../curriculum/teaching_context.dart';
import '../resources/resource_manager.dart';
import 'embedding_request.dart';
import '../resources/resource_manifest.dart';

/// One retrieved curriculum excerpt.
class Chunk {
  const Chunk({
    required this.id,
    required this.chapter,
    required this.title,
    required this.text,
    required this.pageStart,
    required this.pageEnd,
    required this.score,
  });
  final String id;
  final int chapter;
  final String title;
  final String text;
  final int pageStart;
  final int pageEnd;
  final double score;
}

/// A grounded prompt split into the two chat roles.
class GroundedPrompt {
  const GroundedPrompt(this.system, this.user, this.hits);
  final String system;
  final String user;
  final List<Chunk> hits;
}

/// On-device RAG: embed the topic with **bge-small-en-v1.5** (GGUF, CLS pooling)
/// via llama.cpp, brute-force cosine over the bundled `curriculum.db` (167 chunks,
/// 384-dim float32 BLOBs), then assemble a curriculum-grounded prompt. This mirrors
/// the off-device `pipeline/src/rag_prompt.py` exactly — verified identical retrieval
/// (cosine 0.9999998 query parity) so on-device results match the validated pipeline.
/// See docs/decisions/ADR-004.
class RagService {
  RagService({
    TeachingContext? teachingContext,
    Duration embeddingTimeout = const Duration(seconds: 30),
  }) : _module = CurriculumModuleRegistry.resolve(teachingContext),
       _embeddingRequests = EmbeddingRequestRunner(timeout: embeddingTimeout);

  static const int dim = 384;

  final CurriculumModuleAssets _module;
  final EmbeddingRequestRunner _embeddingRequests;

  String get moduleId => _module.moduleId;
  String get curriculumAsset => _module.ragAsset;
  LlamaParent? _embedder;
  Database? _db;
  final Map<String, String> _templates = {}; // kind -> raw template text

  bool get isReady => _embedder != null && _db != null;

  /// Exercise blocks are question lists, not explanatory facts — exclude them from
  /// grounding (matches rag_prompt.py EXCLUDE_TYPES + the OCR-tolerant title regex).
  static final RegExp _exerciseTitle = RegExp(
    r'encircle|select\s*the|give\s*answer|write\s*short|construct(ed)?\s*response|'
    r'answer\s*the\s*following|briefly\s*describe|fill\s*in|differentiate|'
    r'investigate|project|tick\b|match\s*the',
    caseSensitive: false,
  );

  bool _isExercise(String blockType, String title) =>
      blockType == 'exercise' || _exerciseTitle.hasMatch(title);

  /// Load the embedding model + curriculum DB + prompt templates. Idempotent.
  Future<void> init() async {
    if (isReady) return;
    await dispose();
    try {
      // Resolve and verify the managed embedding model before allocating the DB.
      final modelPath = await _resolveEmbeddingModelPath();

      // --- curriculum.db: copy the read-only asset to a file sqlite3 can open. ---
      final support = await getApplicationSupportDirectory();
      final safeModuleId = _module.moduleId.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final dbPath = p.join(support.path, 'curriculum.$safeModuleId.db');
      final dbBytes = await rootBundle.load(_module.ragAsset);
      await File(
        dbPath,
      ).writeAsBytes(dbBytes.buffer.asUint8List(), flush: true);
      _db = sqlite3.open(dbPath, mode: OpenMode.readOnly);

      // --- prompt templates (bundled copies of prompts/*.md). ---
      _templates['mcq'] = await rootBundle.loadString('assets/prompts/mcq.md');
      _templates['lesson'] = await rootBundle.loadString(
        'assets/prompts/lesson_plan.md',
      );

      // --- bge embedder: GGUF in an embeddings-only context, CLS pooling. ---
      Llama.libraryPath = 'libmtmd.so';
      final load = LlamaLoad(
        path: modelPath,
        modelParams: ModelParams()
          ..nGpuLayers = 0
          ..mainGpu = -1,
        contextParams: ContextParams()
          ..nCtx = 512
          ..nBatch = 512
          ..nThreads = 4
          ..nThreadsBatch = 4
          ..embeddings =
              true // embeddings-only context
          ..poolingType =
              LlamaPoolingType.cls, // bge-small-en-v1.5 uses CLS pooling
        samplingParams: SamplerParams(),
        verbose: false,
      );
      _embedder = LlamaParent(load);
      await _embedder!.init();
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  /// Retrieve the top-[k] non-exercise chunks for [query] by cosine similarity.
  /// The corpus is paragraph-level (chunk_fine.py). k=6 dense paragraphs give
  /// BETTER topic coverage than whole sections in far FEWER chars (~2.7 K vs ~5 K;
  /// offline check: k=6 keeps full fact coverage while trimming 20–50% vs k=8) —
  /// faster prefill AND higher quality. The char budget still caps it.
  Future<List<Chunk>> retrieve(String query, {int k = 6}) async {
    final embedder = _embedder;
    final db = _db;
    if (embedder == null || db == null) {
      throw StateError('RagService not initialized — call init() first.');
    }
    final values = await _embeddingRequests.run(
      request: () => embedder.getEmbeddings(query),
      reset: _resetEmbedder,
    );
    if (values.length != dim) {
      await _resetEmbedder();
      throw LocalEmbeddingException(
        'Curriculum search returned ${values.length} values instead of $dim. '
        'The local retrieval model was reset; try again.',
      );
    }
    final q = Float32List.fromList(values);

    final rows = db.select(
      'SELECT id, chapter, title, block_type, page_start, page_end, text, '
      'embedding FROM chunks',
    );
    final scored = <Chunk>[];
    for (final r in rows) {
      final blockType = (r['block_type'] as String?) ?? '';
      final title = (r['title'] as String?) ?? '';
      if (_isExercise(blockType, title)) continue;
      final blob = r['embedding'] as Uint8List;
      final vec = blob.buffer.asFloat32List(blob.offsetInBytes, dim);
      double sim = 0;
      for (var i = 0; i < dim; i++) {
        sim += q[i] * vec[i]; // both L2-normalized → dot == cosine
      }
      scored.add(
        Chunk(
          id: r['id'] as String,
          chapter: (r['chapter'] as int?) ?? 0,
          title: title,
          text: (r['text'] as String?) ?? '',
          pageStart: (r['page_start'] as int?) ?? 0,
          pageEnd: (r['page_end'] as int?) ?? 0,
          score: sim,
        ),
      );
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(k).toList();
  }

  /// Build the grounded (system, user) prompt for [kind] ('mcq' | 'lesson').
  Future<GroundedPrompt> assemble(
    String kind,
    String topic, {
    int k = 6,
    int expectedCount = 10,
    TeachingContext? teachingContext,
  }) async {
    final template = _templates[kind];
    if (template == null) throw ArgumentError('Unknown prompt kind: $kind');
    final hits = await retrieve(topic, k: k);

    final filled = template
        .replaceAll('{{topic}}', topic)
        .replaceAll('{{count}}', '$expectedCount')
        .replaceAll('{{class}}', teachingContext?.className ?? 'Class 6')
        .replaceAll(
          '{{subject}}',
          teachingContext?.subjectName ?? 'General Science',
        )
        .replaceAll('{{slos}}', _deriveSlos(hits))
        .replaceAll('{{context}}', _buildContext(hits));

    // Templates are "… ## SYSTEM … ## USER …". Split into the two roles.
    final afterSys = filled.split('## SYSTEM');
    final parts = afterSys.last.split('## USER');
    final system = parts.first.trim();
    final user = parts.length > 1 ? parts[1].trim() : '';
    return GroundedPrompt(system, user, hits);
  }

  /// Total grounding-context budget in characters (~4 chars/token). The RAG
  /// prefill dominates latency AND a long KV cache slows every generated token
  /// (on-device bench: gen at 1 K-token depth is ~half the context-free rate), so
  /// bounding the context speeds up *both* halves. ~3000 chars ≈ 750 tokens keeps
  /// the top excerpts intact while cutting the prefill materially.
  static const int _contextCharBudget = 3000;

  /// Cap each excerpt at 1200 chars so one long section can't eat the whole budget.
  static const int _perExcerptCharCap = 1200;

  String _buildContext(List<Chunk> hits) {
    final blocks = <String>[];
    var used = 0;
    for (var i = 0; i < hits.length; i++) {
      if (used >= _contextCharBudget) break;
      final h = hits[i];
      final pages = h.pageStart == h.pageEnd
          ? 'p${h.pageStart}'
          : 'p${h.pageStart}-${h.pageEnd}';
      final cap = _perExcerptCharCap < _contextCharBudget - used
          ? _perExcerptCharCap
          : _contextCharBudget - used;
      final body = _truncateAtSentence(h.text.trim(), cap);
      used += body.length;
      blocks.add(
        '<<<CURRICULUM SOURCE ${i + 1}: Ch ${h.chapter}, ${h.title} ($pages)>>>\n'
        '$body\n'
        '<<<END CURRICULUM SOURCE ${i + 1}>>>',
      );
    }
    return blocks.join('\n\n');
  }

  /// Truncate [text] to at most [maxChars], preferring to cut at the last sentence
  /// end (. ! ?) or newline so the model never sees a mid-sentence fragment.
  static String _truncateAtSentence(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final cut = text.substring(0, maxChars);
    var end = cut.lastIndexOf(RegExp(r'[.!?]\s'));
    final nl = cut.lastIndexOf('\n');
    if (nl > end) end = nl;
    // Only honor the boundary if it keeps a reasonable amount (>60% of the cap).
    if (end > maxChars * 0.6) return cut.substring(0, end + 1).trim();
    return '${cut.trim()}…';
  }

  /// Rough SLO list = the distinct section titles retrieved (v1, matches Python).
  String _deriveSlos(List<Chunk> hits) {
    final seen = <String>{};
    final out = <String>[];
    for (final h in hits) {
      final t = h.title.trim();
      if (t.isNotEmpty && seen.add(t)) out.add(t);
    }
    return out.take(4).join('; ');
  }

  /// Resolve only an app-managed embedding model whose downloaded file
  /// matches the size and SHA-256 declared in the bundled manifest.
  Future<String> _resolveEmbeddingModelPath() async {
    final manager = ResourceManager();
    try {
      await manager.init();
      final models = manager.resources(kind: ResourceKind.embeddingModel);
      if (models.isEmpty) {
        throw FileSystemException('No approved embedding model is configured.');
      }
      final installed = await manager.installedFile(models.first.id);
      if (installed == null) {
        throw FileSystemException('Embedding model is not installed.');
      }
      return installed.path;
    } finally {
      manager.dispose();
    }
  }

  Future<void> _resetEmbedder() async {
    final embedder = _embedder;
    _embedder = null;
    await embedder?.dispose();
  }

  /// Release the native embedding allocation while keeping lightweight prompt
  /// and database state available for the current screen.
  Future<void> releaseNativeModel() => _resetEmbedder();

  Future<void> dispose() async {
    await _resetEmbedder();
    _db?.close();
    _db = null;
  }
}
