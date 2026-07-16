import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import '../rag/rag_service.dart';
import 'llama_cpp_service.dart';
import 'mcq_grammar.dart';
import 'mcq_parser.dart';
import 'mcq_test_view.dart';

/// Existing on-device fallback for topics outside the shipped content pack.
/// It remains secondary because it is slower and its content is not pre-verified.
class GenerationScreen extends StatefulWidget {
  const GenerationScreen({super.key, this.initialTopic});

  final String? initialTopic;

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

enum _Phase { idle, preparing, retrieving, loadingModel, generating }

class _GenerationScreenState extends State<GenerationScreen> {
  static const String _modelFile = 'lfm2-1.2b.gguf';

  final _rag = RagService();
  final _llama = LlamaCppService();
  final _library = LibraryStore();
  late final _topic = TextEditingController(text: widget.initialTopic ?? '');

  String _kind = 'mcq';
  _Phase _phase = _Phase.idle;
  List<Chunk> _hits = [];
  String _output = '';
  final StringBuffer _buffer = StringBuffer();
  Timer? _uiTimer;
  McqTest? _test;
  bool _saved = false;
  String? _error;
  Duration _elapsed = Duration.zero;
  int _chunks = 0;

  bool get _busy => _phase != _Phase.idle;
  double get _tokPerSec => _elapsed.inMilliseconds == 0
      ? 0
      : _chunks / (_elapsed.inMilliseconds / 1000);

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
    if (topic.isEmpty || _busy) return;
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
      await _rag.init();
      if (!mounted) return;
      setState(() => _phase = _Phase.retrieving);
      final grounded = await _rag.assemble(_kind, topic);
      if (!mounted) return;
      setState(() {
        _hits = grounded.hits;
        _phase = _Phase.loadingModel;
      });

      await _llama.load(
        _modelFile,
        grammar: _kind == 'mcq' ? kMcqGrammar : null,
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.generating);

      final stopwatch = Stopwatch()..start();
      _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() {
          _output = _clean(_buffer.toString());
          _elapsed = stopwatch.elapsed;
        });
      });

      await for (final chunk
          in _llama.generateChat(grounded.system, grounded.user)) {
        _buffer.write(chunk);
        _chunks++;
      }
      stopwatch.stop();
      _uiTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _output = _clean(_buffer.toString());
        _elapsed = stopwatch.elapsed;
        if (_kind == 'mcq') {
          _test = McqParser.parse(_output, topic: topic);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _uiTimer?.cancel();
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  static String _clean(String value) => value
      .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
      .trimLeft();

  Future<void> _save() async {
    if (_output.isEmpty || _saved) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final test = _test;
    await _library.save(SavedTest(
      id: test?.id ?? now.toString(),
      kind: _kind,
      topic: _topic.text.trim(),
      rawOutput: _output,
      contentJson: test?.toJson(),
      createdAtMillis: now,
      excerptTitles: _hits.map((hit) => hit.title).toList(),
    ));
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Library')),
      );
    }
  }

  String get _phaseLabel => switch (_phase) {
        _Phase.idle => _chunks > 0
            ? 'Finished in ${_elapsed.inSeconds}s · ${_tokPerSec.toStringAsFixed(1)} tok/s'
            : 'Ready when the local model files are installed.',
        _Phase.preparing => 'Preparing the curriculum search…',
        _Phase.retrieving => 'Finding relevant textbook sections…',
        _Phase.loadingModel => 'Loading the local LFM2 model…',
        _Phase.generating =>
          'Writing on-device · ${_elapsed.inSeconds}s · ${_tokPerSec.toStringAsFixed(1)} tok/s',
      };

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final sections = [
      for (final hit in _hits)
        if (seen.add(hit.title)) hit,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Custom topic generation')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BayazCard(
                color: AppColors.softGold,
                borderColor: const Color(0xFFFFD96A),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.warningText),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'This is the existing fallback for topics not covered by the verified pack. It runs fully on-device, takes several minutes, and the result should be checked before use.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.warningText,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'mcq',
                    label: Text('MCQ test'),
                    icon: Icon(Icons.fact_check_outlined),
                  ),
                  ButtonSegment(
                    value: 'lesson',
                    label: Text('Lesson plan'),
                    icon: Icon(Icons.menu_book_outlined),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() => _kind = value.first),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _topic,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _run(),
                decoration: const InputDecoration(
                  labelText: 'Topic',
                  hintText: 'e.g. renewable energy in Pakistan',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _busy ? null : _run,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(_busy ? 'Working on-device…' : 'Generate'),
              ),
              const SizedBox(height: AppSpacing.md),
              BayazCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_phaseLabel),
                    if (_busy) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
              if (sections.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Textbook grounding',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final hit in sections)
                      StatusChip(
                        label: 'Ch${hit.chapter} · ${hit.title}',
                        icon: Icons.menu_book_outlined,
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                BayazCard(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderColor: Theme.of(context).colorScheme.error,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              if (_test != null && _test!.questions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                McqTestView(
                  test: _test!,
                  onSave: _save,
                  saved: _saved,
                  showReadyAnimation: true,
                ),
              ] else if (_output.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text('Generated lesson plan',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _saved ? null : _save,
                      icon: Icon(_saved
                          ? Icons.bookmark_added_rounded
                          : Icons.bookmark_add_outlined),
                      label: Text(_saved ? 'Saved' : 'Save'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                BayazCard(
                  child: SelectableText(
                    _output,
                    style: const TextStyle(height: 1.5),
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
