import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/long_operation_panel.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../chat/clarification_context.dart';
import '../chat/clarification_screen.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import '../rag/rag_service.dart';
import '../resources/local_ai_resources.dart';
import 'generated_output_sanitizer.dart';
import 'lesson_plan.dart';
import 'lesson_plan_parser.dart';
import 'local_model_handoff.dart';
import 'lesson_plan_view.dart';
import 'llama_cpp_service.dart';
import 'mcq_grammar.dart';
import 'mcq_parser.dart';
import 'mcq_test_view.dart';

/// Existing on-device fallback for topics outside the shipped content pack.
/// It remains secondary because it is slower and its content is not pre-verified.
class GenerationScreen extends StatefulWidget {
  const GenerationScreen({
    super.key,
    this.initialTopic,
    this.initialKind = 'mcq',
  });

  final String? initialTopic;
  final String initialKind;

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

enum _Phase { idle, preparing, retrieving, loadingModel, generating }

class _GenerationScreenState extends State<GenerationScreen> {
  final _rag = RagService();
  final _llama = LlamaCppService();
  final _modelHandoff = const LocalModelHandoff();
  final _library = LibraryStore();
  final _localAi = LocalAiResources();
  late final _topic = TextEditingController(text: widget.initialTopic ?? '');

  late String _kind = widget.initialKind == 'lesson' ? 'lesson' : 'mcq';
  _Phase _phase = _Phase.idle;
  List<Chunk> _hits = [];
  String _output = '';
  final StringBuffer _buffer = StringBuffer();
  Timer? _uiTimer;
  McqTest? _test;
  LessonPlan? _lessonPlan;
  List<String> _missingLessonSections = const [];
  bool _grounded = true;
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
    unawaited(_rag.dispose());
    unawaited(_llama.unload());
    _localAi.dispose();
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
      _lessonPlan = null;
      _missingLessonSections = const [];
      _grounded = true;
      _saved = false;
      _hits = [];
      _chunks = 0;
      _elapsed = Duration.zero;
      _phase = _Phase.preparing;
    });

    try {
      if (!mounted) return;
      setState(() => _phase = _Phase.retrieving);
      final prompt = await _modelHandoff.retrieve(
        releaseGenerator: _llama.unload,
        releaseRetriever: _rag.releaseNativeModel,
        runRetrieval: () async {
          try {
            await _rag.init();
            return await _rag.assemble(_kind, topic);
          } on FileSystemException {
            _grounded = false;
            return GroundedPrompt(
              'You are Bayaz AI, an offline teaching assistant for Pakistan. '
              'The curriculum retrieval model is not installed. Do not claim curriculum '
              'alignment. Use simple language, make uncertainty clear, and produce only '
              'the requested format.',
              _kind == 'mcq'
                  ? 'Create exactly 10 MCQs about "$topic". For each item output: '
                      'Q<number>. <stem>, then A) through D) on separate lines, then '
                      'ANSWER: <A|B|C|D>, then DIFFICULTY: <easy|medium|hard>. '
                      'Do not add any other sections.'
                  : 'Create a practical 50-minute 5E lesson plan about "$topic". '
                      'Use these exact Markdown headers in this order: ### Objectives, '
                      '### Materials, ### Revision starter (5 min), ### Engage (5 min), '
                      '### Explore (12 min), ### Explain (12 min), ### Socratic questions, '
                      '### Elaborate (8 min), ### Evaluate (8 min), ### Homework, ### Notes.',
              const [],
            );
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _hits = prompt.hits;
        _phase = _Phase.loadingModel;
      });

      final availability = await _localAi.inspect();
      if (!availability.languageModel.installed ||
          availability.languageModel.file == null) {
        throw StateError(
          'The managed offline language model is not installed. Open setup to download it.',
        );
      }
      await _llama.loadPath(
        availability.languageModel.file!.path,
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
          in _llama.generateChat(prompt.system, prompt.user)) {
        _buffer.write(chunk);
        _chunks++;
      }
      stopwatch.stop();
      _uiTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _output = _clean(_buffer.toString(), finalOutput: true);
        _elapsed = stopwatch.elapsed;
        if (_kind == 'mcq') {
          _test = McqParser.parse(_output, topic: topic);
        } else {
          final parsed = LessonPlanParser.parse(_output, topic: topic);
          _lessonPlan = parsed.plan;
          _missingLessonSections = parsed.missingSections;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      _uiTimer?.cancel();
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('No such file') || text.contains('not installed')) {
      return 'Offline AI files are not installed. Open setup to download the language and retrieval models, then try again.';
    }
    return text;
  }

  String _clean(String value, {bool finalOutput = false}) =>
      GeneratedOutputSanitizer.sanitize(
        value,
        finalOutput: finalOutput,
        lessonPlan: _kind == 'lesson',
      );

  Future<void> _save() async {
    if (_output.isEmpty || _saved) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final test = _test;
    await _library.save(SavedTest(
      id: test?.id ?? now.toString(),
      kind: _kind,
      source: SavedContentSource.customAi,
      topic: _topic.text.trim(),
      rawOutput: _output,
      contentJson: test?.toJson() ?? _lessonPlan?.toJson(),
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
              if (_busy)
                LongOperationPanel(
                  primaryStatus: _phaseLabel,
                  messages: const [
                    'Preparing the chalkboard…',
                    'Searching the science shelf…',
                    'Connecting the lesson pieces…',
                    'Checking the tricky parts…',
                    'Making it classroom-ready…',
                  ],
                )
              else
                BayazCard(child: Text(_phaseLabel)),
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
              if (!_grounded && (_busy || _output.isNotEmpty)) ...[
                const SizedBox(height: AppSpacing.md),
                BayazCard(
                  color: AppColors.softGold,
                  borderColor: const Color(0xFFFFD96A),
                  child: const Text(
                    'Ungrounded mode: the retrieval model was unavailable, so this output comes from the language model’s own knowledge. Review every fact before classroom use.',
                  ),
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
              ] else if (_lessonPlan != null && _lessonPlan!.sections.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text('Generated lesson plan',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'Ask about this lesson',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ClarificationScreen(
                            contextMaterial: ClarificationContext.lesson(
                              _lessonPlan!,
                            ),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.forum_outlined),
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
                if (_missingLessonSections.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  BayazCard(
                    color: AppColors.softGold,
                    borderColor: const Color(0xFFFFD96A),
                    child: Text(
                      'The model omitted: ${_missingLessonSections.join(', ')}. The parsed sections are shown below; review the plan before saving.',
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.72,
                  child: LessonPlanDocument(plan: _lessonPlan!),
                ),
              ] else if (_output.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                BayazCard(
                  color: AppColors.softGold,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Could not structure this response',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      const Text('The model did not follow the required section contract. The raw response is kept below for recovery.'),
                      const SizedBox(height: AppSpacing.sm),
                      SelectableText(_output),
                    ],
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
