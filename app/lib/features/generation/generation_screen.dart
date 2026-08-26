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
import '../curriculum/teaching_context.dart';
import '../curriculum/recent_work_store.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import '../rag/rag_service.dart';
import '../resources/local_ai_resources.dart';
import '../resources/offline_ai_gate.dart';
import '../resources/offline_ai_navigation.dart';
import '../resources/offline_ai_policy.dart';
import 'generated_output_sanitizer.dart';
import 'generation_progress.dart';
import 'lesson_plan.dart';
import 'lesson_plan_parser.dart';
import 'lesson_plan_view.dart';
import 'llama_cpp_service.dart';
import 'local_ai_route_lifecycle.dart';
import 'local_model_handoff.dart';
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
    this.offlineAiPolicy,
    this.dedicated = false,
    this.teachingContext,
    this.expectedCount = 10,
    this.generateLessonOverride,
    this.generateTestOverride,
  });

  final String? initialTopic;
  final String initialKind;
  final OfflineAiPolicy? offlineAiPolicy;
  final bool dedicated;
  final TeachingContext? teachingContext;
  final int expectedCount;
  final Future<LessonPlan> Function(String topic)? generateLessonOverride;
  final Future<McqTest> Function(String topic, int count)? generateTestOverride;

  @override
  State<GenerationScreen> createState() => _GenerationScreenState();
}

enum _Phase { idle, preparing, retrieving, loadingModel, generating }

class _GenerationScreenState extends State<GenerationScreen> {
  final _rag = RagService();
  final _llama = LlamaCppService();
  final _modelHandoff = const LocalModelHandoff();
  final _routeLifecycle = LocalAiRouteLifecycle();
  final _library = LibraryStore();
  final _localAi = LocalAiResources();
  late final OfflineAiPolicy _offlineAiPolicy;
  late final _topic = TextEditingController(text: widget.initialTopic ?? '');

  late String _kind = widget.initialKind == 'lesson' ? 'lesson' : 'mcq';
  late int _expectedCount = widget.expectedCount;
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
  Future<void>? _activeOperation;
  bool _allowPop = false;
  bool _localResourcesDisposed = false;

  @override
  void initState() {
    super.initState();
    _offlineAiPolicy = widget.offlineAiPolicy ?? OfflineAiPolicy();
  }

  bool get _busy => _phase != _Phase.idle || _routeLifecycle.closing;
  double get _tokPerSec => _elapsed.inMilliseconds == 0
      ? 0
      : _chunks / (_elapsed.inMilliseconds / 1000);

  @override
  void dispose() {
    _routeLifecycle.cancelOperations();
    _uiTimer?.cancel();
    _topic.dispose();
    unawaited(_routeLifecycle.close(_cleanup));
    super.dispose();
  }

  Future<void> _run() {
    final topic = _topic.text.trim();
    if (topic.isEmpty || _busy) return Future<void>.value();
    final token = _routeLifecycle.beginOperation();
    final operation = _runOperation(token, topic);
    _activeOperation = operation;
    return operation.whenComplete(() {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    });
  }

  Future<void> _runOperation(int token, String topic) async {
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

    final lessonOverride = widget.generateLessonOverride;
    if (_kind == 'lesson' && lessonOverride != null) {
      try {
        final plan = await lessonOverride(topic);
        if (!_canUpdate(token)) return;
        setState(() {
          _lessonPlan = plan;
          _phase = _Phase.idle;
        });
      } catch (e) {
        if (_canUpdate(token)) {
          setState(() {
            _error = _displayError(e);
            _phase = _Phase.idle;
          });
        }
      }
      return;
    }

    final testOverride = widget.generateTestOverride;
    if (_kind == 'mcq' && testOverride != null) {
      try {
        final test = await testOverride(topic, _expectedCount);
        if (!_canUpdate(token)) return;
        setState(() {
          _test = test;
          _phase = _Phase.idle;
        });
      } catch (e) {
        if (_canUpdate(token)) {
          setState(() {
            _error = _displayError(e);
            _phase = _Phase.idle;
          });
        }
      }
      return;
    }

    try {
      await _offlineAiPolicy.requireEnabled();
      if (!_canUpdate(token)) return;
      setState(() => _phase = _Phase.retrieving);
      final prompt = await _modelHandoff.retrieve(
        releaseGenerator: _llama.unload,
        releaseRetriever: _rag.releaseNativeModel,
        runRetrieval: () async {
          try {
            await _rag.init();
            return await _rag.assemble(
              _kind,
              topic,
              expectedCount: _expectedCount,
              teachingContext: widget.teachingContext,
            );
          } on FileSystemException {
            _grounded = false;
            return GroundedPrompt(
              'You are Bayaz AI, an offline teaching assistant for Pakistan. '
              'The curriculum retrieval model is not installed. Do not claim curriculum '
              'alignment. Use simple language, make uncertainty clear, and produce only '
              'the requested format.',
              _kind == 'mcq'
                  ? 'Create exactly $_expectedCount MCQs about "$topic". For each item output: '
                        'Q<number> [easy|medium|hard], then the question text, then A) through D) on separate lines, then '
                        'ANSWER: <A|B|C|D>. '
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
      if (!_canUpdate(token)) return;
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
        grammar: _kind == 'mcq' ? mcqGrammarForCount(_expectedCount) : null,
      );
      if (!_canUpdate(token)) return;
      setState(() => _phase = _Phase.generating);

      final stopwatch = Stopwatch()..start();
      _uiTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!_canUpdate(token)) return;
        setState(() {
          _output = _clean(_buffer.toString());
          _elapsed = stopwatch.elapsed;
        });
      });

      await for (final chunk in _llama.generateChat(
        prompt.system,
        prompt.user,
      )) {
        if (!_canUpdate(token)) break;
        _buffer.write(chunk);
        _chunks++;
      }
      stopwatch.stop();
      _uiTimer?.cancel();
      if (!_canUpdate(token)) return;
      setState(() {
        _output = _clean(_buffer.toString(), finalOutput: true);
        _elapsed = stopwatch.elapsed;
        if (_kind == 'mcq') {
          _test = McqParser.parse(
            _output,
            topic: topic,
            expectedCount: _expectedCount,
          );
        } else {
          final parsed = LessonPlanParser.parse(_output, topic: topic);
          _lessonPlan = parsed.plan;
          _missingLessonSections = parsed.missingSections;
        }
      });
    } catch (e) {
      if (_canUpdate(token)) setState(() => _error = _friendlyError(e));
    } finally {
      _uiTimer?.cancel();
      if (_canUpdate(token)) setState(() => _phase = _Phase.idle);
    }
  }

  bool _canUpdate(int token) => mounted && _routeLifecycle.isCurrent(token);

  Future<void> _closeAndPop() async {
    if (_routeLifecycle.closing) return;
    final close = _routeLifecycle.close(_cleanup);
    if (mounted) setState(() {});
    await finishLocalAiRouteClose(
      close,
      description: 'closing the generation screen',
      isMounted: () => mounted,
      allowPop: () => setState(() => _allowPop = true),
      pop: () => unawaited(Navigator.of(context).maybePop()),
    );
  }

  Future<void> _cleanup() async {
    _uiTimer?.cancel();
    try {
      await _llama.unload();
    } catch (_) {
      // Continue releasing the remaining route resources.
    }
    final active = _activeOperation;
    if (active != null) {
      try {
        await active;
      } catch (_) {
        // The closing route no longer surfaces operation errors.
      }
    }
    try {
      await _rag.dispose();
    } catch (_) {
      // Continue with synchronous resource cleanup.
    }
    if (!_localResourcesDisposed) {
      _localResourcesDisposed = true;
      _localAi.dispose();
    }
  }

  String _displayError(Object error) {
    if (widget.dedicated) {
      if (error is OfflineAiDisabledException) {
        return 'Bayaz is still preparing offline tools. Try again when setup is ready.';
      }
      final text = error.toString();
      if (text.contains('No such file') || text.contains('not installed')) {
        return 'Bayaz is still preparing offline tools. Try again when setup is ready.';
      }
      return 'Bayaz could not create this right now. Please try again.';
    }
    return _friendlyError(error);
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (error is OfflineAiDisabledException) {
      return 'Offline AI is turned off. Enable it in teacher setup before generating custom content.';
    }
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
    if ((_output.isEmpty && _test == null && _lessonPlan == null) || _saved) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final test = _test;
    final savedId = test?.id ?? now.toString();
    await _library.save(
      SavedTest(
        id: savedId,
        kind: _kind,
        source: SavedContentSource.customAi,
        topic: _topic.text.trim(),
        rawOutput: _output,
        contentJson: test?.toJson() ?? _lessonPlan?.toJson(),
        createdAtMillis: now,
        excerptTitles: _hits.map((hit) => hit.title).toList(),
        teachingContext: widget.teachingContext,
      ),
    );
    unawaited(
      RecentWorkStore()
          .update(
            RecentWorkReference(
              type: _kind == 'lesson' ? 'lesson' : 'test',
              id: savedId,
            ),
          )
          .catchError((_) {}),
    );
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved in Bayaz')));
    }
  }

  Widget _operationPanel({
    required String primaryStatus,
    required List<String> messages,
  }) {
    final progress = _phase == _Phase.generating
        ? (_kind == 'mcq'
              ? GenerationProgress.mcq(_output, _expectedCount)
              : GenerationProgress.lesson(_output))
        : null;
    final progressLabel = progress == null
        ? null
        : _kind == 'mcq'
        ? '${progress.completed} of ${progress.total} questions ready'
        : '${progress.completed} of ${progress.total} sections ready';
    return LongOperationPanel(
      primaryStatus: primaryStatus,
      messages: messages,
      progress: progress?.fraction,
      progressLabel: progressLabel,
    );
  }

  String get _phaseLabel => switch (_phase) {
    _Phase.idle when _routeLifecycle.closing => 'Closing offline AI safely…',
    _Phase.idle =>
      _chunks > 0
          ? 'Finished in ${_elapsed.inSeconds}s · ${_tokPerSec.toStringAsFixed(1)} tok/s'
          : 'Ready when the local model files are installed.',
    _Phase.preparing => 'Preparing the curriculum search…',
    _Phase.retrieving => 'Finding relevant textbook sections…',
    _Phase.loadingModel => 'Loading the local LFM2 model…',
    _Phase.generating =>
      'Writing on-device · ${_elapsed.inSeconds}s · ${_tokPerSec.toStringAsFixed(1)} tok/s',
  };

  @override
  Widget build(BuildContext context) => OfflineAiGate(
    title: 'Custom topic generation',
    policy: _offlineAiPolicy,
    enabledBuilder: _buildEnabled,
  );

  Widget _buildEnabled(BuildContext context) {
    if (widget.dedicated && _test != null) {
      return McqTestScreen(
        test: _test!,
        teachingContext: widget.teachingContext,
        onSave: _save,
        saved: _saved,
      );
    }
    if (widget.dedicated && _lessonPlan != null) {
      return LessonPlanScreen(
        plan: _lessonPlan!,
        teachingContext: widget.teachingContext,
        onSave: _save,
        initiallySaved: _saved,
      );
    }
    if (widget.dedicated) return _buildDedicated(context);

    final seen = <String>{};
    final sections = [
      for (final hit in _hits)
        if (seen.add(hit.title)) hit,
    ];

    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeAndPop());
      },
      child: Scaffold(
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
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.warningText,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'This is the existing fallback for topics not covered by the verified pack. It runs fully on-device, takes several minutes, and the result should be checked before use.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.warningText),
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
                  _operationPanel(
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
                  Text(
                    'Textbook grounding',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                ] else if (_lessonPlan != null &&
                    _lessonPlan!.sections.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Generated lesson plan',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ask about this lesson',
                        onPressed: () => openOfflineAiScreen(
                          context,
                          (_) => ClarificationScreen(
                            contextMaterial: ClarificationContext.lesson(
                              _lessonPlan!,
                            ),
                          ),
                          policy: _offlineAiPolicy,
                        ),
                        icon: const Icon(Icons.forum_outlined),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _saved ? null : _save,
                        icon: Icon(
                          _saved
                              ? Icons.bookmark_added_rounded
                              : Icons.bookmark_add_outlined,
                        ),
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
                        Text(
                          'Could not structure this response',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'The model did not follow the required section contract. The raw response is kept below for recovery.',
                        ),
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
      ),
    );
  }

  Widget _buildDedicated(BuildContext context) {
    final isLesson = _kind == 'lesson';
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeAndPop());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isLesson ? 'Create custom lesson' : 'Create custom test'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              TextField(
                controller: _topic,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _run(),
                decoration: const InputDecoration(
                  labelText: 'Topic',
                  hintText: 'Enter the topic',
                ),
              ),
              if (!isLesson) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Number of questions',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final count in const [5, 10, 15])
                      ChoiceChip(
                        label: Text('$count'),
                        selected: _expectedCount == count,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _expectedCount = count),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _busy ? null : _run,
                child: Text(
                  _busy
                      ? 'Preparing…'
                      : isLesson
                      ? 'Create lesson'
                      : 'Create test',
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: AppSpacing.md),
                _operationPanel(
                  primaryStatus: 'Preparing your classroom material…',
                  messages: const [
                    'Finding the most useful teaching points…',
                    'Putting the classroom material together…',
                    'Checking the final structure…',
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                BayazCard(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderColor: Theme.of(context).colorScheme.error,
                  child: Text(_error!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
