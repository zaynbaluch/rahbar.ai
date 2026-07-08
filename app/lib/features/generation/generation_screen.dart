import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../export/pdf_export.dart';
import '../rag/rag_service.dart';
import 'llama_cpp_service.dart';
import 'mcq_parser.dart';
import 'model_spike_screen.dart';

/// The real generate-and-review flow: pick a topic, the app runs **on-device RAG**
/// (bge-small query embedding → cosine over the bundled curriculum.db) to build a
/// grounded prompt, then streams a **Qwen3 1.7B** (greedy) lesson plan or MCQ test.
/// This is the validated end-to-end pipeline from ADR-003/004.
class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key});

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

enum _Phase { idle, preparing, retrieving, loadingModel, generating }

class _GenerationScreenState extends State<GenerationScreen> {
  static const String _modelFile = 'qwen3-1.7b.gguf';

  final _rag = RagService();
  final _llama = LlamaCppService();
  final _topic = TextEditingController(text: 'the human digestive system');

  String _kind = 'mcq'; // 'mcq' | 'lesson'
  _Phase _phase = _Phase.idle;
  List<Chunk> _hits = [];
  String _output = '';
  McqTest? _test; // parsed structured test (MCQ mode only)
  bool _showAnswers = false;
  String? _error;

  Duration _elapsed = Duration.zero;
  int _chunks = 0;
  double get _tokPerSec =>
      _elapsed.inMilliseconds == 0 ? 0 : _chunks / (_elapsed.inMilliseconds / 1000);

  bool get _busy => _phase != _Phase.idle;

  @override
  void dispose() {
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
      _test = null;
      _showAnswers = false;
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

      // 3. Load the generation model.
      setState(() => _phase = _Phase.loadingModel);
      await _llama.load(_modelFile);

      // 4. Stream the grounded generation. /no_think keeps Qwen3 out of its slow
      //    reasoning mode (validated config — see ADR-003).
      setState(() => _phase = _Phase.generating);
      final sw = Stopwatch()..start();
      final stream = _llama.generateChat(grounded.system, '${grounded.user}\n/no_think');
      await for (final chunk in stream) {
        setState(() {
          _output += chunk;
          _chunks++;
          _elapsed = sw.elapsed;
        });
      }
      sw.stop();
      setState(() {
        _elapsed = sw.elapsed;
        // Parse MCQ output into a structured test (foundation for PDF + OMR).
        if (_kind == 'mcq') _test = McqParser.parse(_output, topic: topic);
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  Future<void> _exportPdf() async {
    final test = _test;
    if (test == null) return;
    final bytes = await PdfExport.build(test);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Rahbar-${PdfExport.testId(test.topic)}',
    );
  }

  String get _phaseLabel => switch (_phase) {
        _Phase.idle => _chunks > 0
            ? 'Done · ${_elapsed.inSeconds}s · ${_tokPerSec.toStringAsFixed(1)} tok/s'
            : 'Enter a topic and generate.',
        _Phase.preparing => 'Loading embedder + curriculum…',
        _Phase.retrieving => 'Searching the textbook…',
        _Phase.loadingModel => 'Loading Qwen3 1.7B…',
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
                Text('Grounded in ${_hits.length} textbook excerpts',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final h in _hits)
                      Chip(
                        label: Text('Ch${h.chapter} · ${h.title}  '
                            '(${h.score.toStringAsFixed(2)})'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
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
                _TestHeader(
                  test: _test!,
                  showAnswers: _showAnswers,
                  onToggle: () => setState(() => _showAnswers = !_showAnswers),
                  onExport: _exportPdf,
                ),
                const SizedBox(height: 8),
                for (final q in _test!.questions)
                  _QuestionCard(q: q, showAnswer: _showAnswers),
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

/// Summary banner + answer-key reveal for a parsed MCQ test.
class _TestHeader extends StatelessWidget {
  const _TestHeader({
    required this.test,
    required this.showAnswers,
    required this.onToggle,
    required this.onExport,
  });

  final McqTest test;
  final bool showAnswers;
  final VoidCallback onToggle;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = test.completeCount == test.count;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(complete ? Icons.check_circle : Icons.info_outline,
                color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${test.count} questions'
                '${complete ? '' : ' · ${test.completeCount} complete'}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            TextButton.icon(
              onPressed: onToggle,
              icon: Icon(showAnswers ? Icons.visibility_off : Icons.visibility),
              label: Text(showAnswers ? 'Hide key' : 'Show key'),
            ),
            IconButton(
              tooltip: 'Export / print PDF',
              onPressed: onExport,
              icon: const Icon(Icons.picture_as_pdf),
            ),
          ],
        ),
      ),
    );
  }
}

/// One question rendered as a card; correct option highlighted when [showAnswer].
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.q, required this.showAnswer});

  final McqQuestion q;
  final bool showAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Q${q.number}. ',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(q.text.isEmpty ? '(missing question)' : q.text,
                      style: theme.textTheme.titleSmall),
                ),
                if (q.difficulty.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Chip(
                      label: Text(q.difficulty),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final letter in const ['A', 'B', 'C', 'D'])
              if (q.options.containsKey(letter))
                _OptionRow(
                  letter: letter,
                  text: q.options[letter]!,
                  correct: showAnswer && q.answer == letter,
                ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.letter,
    required this.text,
    required this.correct,
  });

  final String letter;
  final String text;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: correct ? theme.colorScheme.tertiaryContainer : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$letter) ',
              style: TextStyle(
                  fontWeight: correct ? FontWeight.bold : FontWeight.normal)),
          Expanded(child: Text(text)),
          if (correct)
            Icon(Icons.check, size: 18, color: theme.colorScheme.onTertiaryContainer),
        ],
      ),
    );
  }
}
