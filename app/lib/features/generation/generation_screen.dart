import 'dart:async';

import 'package:flutter/material.dart';

import '../library/library_screen.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import '../rag/rag_service.dart';
import 'llama_cpp_service.dart';
import 'mcq_grammar.dart';
import 'mcq_parser.dart';
import 'mcq_test_view.dart';
import 'model_spike_screen.dart';

/// **The escape hatch.** On-device RAG (bge-small → cosine over the bundled
/// `curriculum.db`) into a grounded prompt, then a streamed **LFM2 1.2B** (greedy)
/// generation; MCQ mode is grammar-constrained (mcq_grammar.dart) so the output is
/// parseable and OMR-ready. ADR-003/004.
///
/// This is **no longer the main path**. Lesson plans and tests now come from the
/// pre-generated, verified content pack and appear instantly (ADR-008) — this run costs
/// ~3.5 min and its answer keys have never been checked by anything. It exists for topics
/// outside the shipped curriculum, so "it generates for anything, offline" stays true.
class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key, this.initialTopic});

  /// Pre-fills the topic box — set when arriving from a failed search in the picker.
  final String? initialTopic;

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

enum _Phase { idle, preparing, retrieving, loadingModel, generating }

class _GenerationScreenState extends State<GenerationScreen> {
  // LFM2-1.2B is the shipping model after the ADR-003 speed bake-off: ~2× Qwen3's
  // decode on CPU, with MCQ schema guaranteed by grammar-constrained decoding.
  static const String _modelFile = 'lfm2-1.2b.gguf';

  final _rag = RagService();
  final _llama = LlamaCppService();
  final _library = LibraryStore();
  late final _topic = TextEditingController(text: widget.initialTopic ?? '');

  String _kind = 'mcq'; // 'mcq' | 'lesson'
  _Phase _phase = _Phase.idle;
  List<Chunk> _hits = [];
  String _output = '';
  final StringBuffer _buffer = StringBuffer(); // tokens land here; flushed to UI on a timer
  Timer? _uiTimer;
  McqTest? _test; // parsed structured test (MCQ mode only)
  bool _saved = false;
  String? _error;

  Duration _elapsed = Duration.zero;
  int _chunks = 0;
  double get _tokPerSec =>
      _elapsed.inMilliseconds == 0 ? 0 : _chunks / (_elapsed.inMilliseconds / 1000);

  bool get _busy => _phase != _Phase.idle;

  @override
  void dispose() {
    _uiTimer?.cancel();
    _topic.dispose();
    _rag.dispose();
    _llama.unload();
    super.dispose();
  }

  Future<void> _run() async {
    final topic = _topic.text.trim();
    if (topic.isEmpty) return;
    setState(() {
      _error = null;
      _output = '';
      _buffer.clear();
      _test = null;
      _saved = false;
      _hits = [];
      _chunks = 0;
      _elapsed = Duration.zero;
      _phase = _Phase.preparing;
    });
    try {
      // 1. Load the embedder + curriculum DB (idempotent after first run).
      await _rag.init();

      // 2. On-device retrieval → grounded (system, user) prompt.
      setState(() => _phase = _Phase.retrieving);
      final grounded = await _rag.assemble(_kind, topic);
      setState(() => _hits = grounded.hits);

      // 3. Load the generation model. MCQ mode loads with the GBNF grammar so the
      //    output is guaranteed parseable/OMR-ready (see mcq_grammar.dart); lesson
      //    plans run unconstrained. Switching kind reloads the model (rare).
      setState(() => _phase = _Phase.loadingModel);
      await _llama.load(_modelFile, grammar: _kind == 'mcq' ? kMcqGrammar : null);

      // 4. Stream the grounded generation. Tokens are buffered and flushed to the
      //    UI every 200 ms so output streams live without rebuilding the tree on
      //    every token (which starves rendering during heavy CPU).
      setState(() => _phase = _Phase.generating);
      final sw = Stopwatch()..start();
      _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) {
          setState(() {
            _output = _clean(_buffer.toString());
            _elapsed = sw.elapsed;
          });
        }
      });
      final stream = _llama.generateChat(grounded.system, grounded.user);
      await for (final chunk in stream) {
        _buffer.write(chunk);
        _chunks++;
      }
      sw.stop();
      _uiTimer?.cancel();
      setState(() {
        _output = _clean(_buffer.toString());
        _elapsed = sw.elapsed;
        // Parse MCQ output into a structured test (foundation for PDF + OMR).
        if (_kind == 'mcq') _test = McqParser.parse(_output, topic: topic);
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      _uiTimer?.cancel();
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  /// Strip Qwen3's empty `<think>…</think>` block (emitted even with /no_think).
  static String _clean(String s) =>
      s.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trimLeft();

  Future<void> _save() async {
    if (_output.isEmpty) return;
    final saved = SavedTest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      kind: _kind,
      topic: _topic.text.trim(),
      rawOutput: _output,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      excerptTitles: _hits.map((h) => h.title).toList(),
    );
    await _library.save(saved);
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved to library')));
    }
  }

  String get _phaseLabel => switch (_phase) {
        _Phase.idle => _chunks > 0
            ? 'Done · ${_elapsed.inSeconds}s · ${_tokPerSec.toStringAsFixed(1)} tok/s'
            : 'Enter a topic and generate.',
        _Phase.preparing => 'Loading embedder + curriculum…',
        _Phase.retrieving => 'Searching the textbook…',
        _Phase.loadingModel => 'Loading LFM2 1.2B…',
        _Phase.generating =>
          'Generating · ${_tokPerSec.toStringAsFixed(1)} tok/s · ${_elapsed.inSeconds}s',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rahbar AI'),
        actions: [
          IconButton(
            tooltip: 'Saved tests',
            icon: const Icon(Icons.folder_outlined),
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LibraryScreen()),
                    ),
          ),
          IconButton(
            tooltip: 'Model spike',
            icon: const Icon(Icons.science_outlined),
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ModelSpikeScreen()),
                    ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'mcq',
                      label: Text('MCQ Test'),
                      icon: Icon(Icons.checklist)),
                  ButtonSegment(
                      value: 'lesson',
                      label: Text('Lesson Plan'),
                      icon: Icon(Icons.menu_book)),
                ],
                selected: {_kind},
                onSelectionChanged:
                    _busy ? null : (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _topic,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Topic',
                  hintText: 'e.g. the human digestive system',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _run,
                icon: const Icon(Icons.auto_awesome),
                label: Text(_busy ? 'Working…' : 'Generate'),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_phaseLabel, style: theme.textTheme.bodyMedium),
                      if (_busy) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
              if (_hits.isNotEmpty) ...[
                const SizedBox(height: 16),
                Builder(builder: (context) {
                  // Fine chunks repeat section titles; show unique sections (best
                  // score each) so the grounding chips stay clean.
                  final seen = <String>{};
                  final sections = [
                    for (final h in _hits)
                      if (seen.add(h.title)) h,
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Grounded in ${sections.length} textbook sections',
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final h in sections)
                            Chip(
                              label: Text('Ch${h.chapter} · ${h.title}  '
                                  '(${h.score.toStringAsFixed(2)})'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  );
                }),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                  ),
                ),
              ],
              // Structured MCQ test once parsed; raw text while streaming or for
              // lesson plans (which aren't in the MCQ schema).
              if (_test != null && _test!.questions.isNotEmpty) ...[
                const SizedBox(height: 16),
                McqTestView(test: _test!, onSave: _save, saved: _saved),
              ] else if (_output.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Output', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    _output,
                    style: const TextStyle(fontFamily: 'monospace', height: 1.4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
