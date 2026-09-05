import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../curriculum/teaching_context.dart';
import '../generation/generated_output_sanitizer.dart';
import '../generation/llama_cpp_service.dart';
import '../generation/local_ai_route_lifecycle.dart';
import '../generation/local_model_handoff.dart';
import '../rag/rag_service.dart';
import '../resources/local_ai_resources.dart';
import '../resources/offline_ai_gate.dart';
import '../resources/offline_ai_policy.dart';
import '../settings/resource_management_screen.dart';
import 'clarification_context.dart';

List<String> askBayazSuggestionPool(String kind) => kind == 'lesson'
    ? const [
        'Explain this more simply.',
        'Give me a real-life example.',
        'What misconception might students have?',
        'Suggest a quicker activity.',
        'Suggest a no-cost activity.',
        'What if students finish early?',
        'How can I check understanding?',
        'Give me a five-minute recap.',
        'How should I introduce this topic?',
        'What questions should I ask the class?',
      ]
    : const [
        'Explain why question 3 has this answer.',
        'What misconception does this question test?',
        'Which ideas does this test cover most?',
        'How can I reteach the weakest concept?',
        'Give me a simpler explanation for question 5.',
        'Which questions are likely to confuse students?',
        'Give me a short revision activity for this test.',
        'What should I review before students retake this?',
      ];

class ClarificationScreen extends StatefulWidget {
  const ClarificationScreen({
    super.key,
    required this.contextMaterial,
    this.teachingContext,
    this.offlineAiPolicy,
    this.policyEnabledOverride,
    this.readinessOverride,
    this.answerOverride,
    this.onReportIssue,
  });
  final ClarificationContext contextMaterial;
  final TeachingContext? teachingContext;
  final OfflineAiPolicy? offlineAiPolicy;
  final Future<bool> Function()? policyEnabledOverride;
  final Future<bool> Function()? readinessOverride;
  final Future<String> Function(String question)? answerOverride;
  final VoidCallback? onReportIssue;
  @override
  State<ClarificationScreen> createState() => _ClarificationScreenState();
}

class _ClarificationScreenState extends State<ClarificationScreen> {
  final _question = TextEditingController();
  final _scroll = ScrollController();
  late final RagService _rag;
  final _llama = LlamaCppService();
  final _modelHandoff = const LocalModelHandoff();
  final _routeLifecycle = LocalAiRouteLifecycle();
  final _resources = LocalAiResources();
  late final OfflineAiPolicy _offlineAiPolicy;
  final _messages = <_ChatMessage>[];
  bool _busy = false;
  bool _ready = false;
  bool _readinessKnown = false;
  String? _error;
  String? _lastQuestion;
  int _suggestionOffset = 0;
  Future<void>? _activeOperation;
  bool _allowPop = false;
  bool _localResourcesDisposed = false;

  @override
  void initState() {
    super.initState();
    _rag = RagService(teachingContext: widget.teachingContext);
    _offlineAiPolicy = widget.offlineAiPolicy ?? OfflineAiPolicy();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_checkReadiness()),
    );
  }

  @override
  void dispose() {
    _routeLifecycle.cancelOperations();
    _question.dispose();
    _scroll.dispose();
    unawaited(_routeLifecycle.close(_cleanup));
    super.dispose();
  }

  Future<void> _checkReadiness() async {
    try {
      final override = widget.readinessOverride;
      final ready = override != null
          ? await override()
          : (await _resources.inspect()).languageModel.installed;
      if (!mounted) return;
      setState(() {
        _ready = ready;
        _readinessKnown = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _readinessKnown = true;
      });
    }
  }

  List<String> get _suggestions {
    final pool = askBayazSuggestionPool(widget.contextMaterial.kind);
    return List.generate(
      3,
      (index) => pool[(_suggestionOffset + index) % pool.length],
    );
  }

  String get _contextLabel =>
      '${widget.contextMaterial.title} · ${widget.contextMaterial.kind == 'lesson' ? 'Lesson Plan' : 'Test'}';
  String get _inputHint => widget.contextMaterial.kind == 'lesson'
      ? 'Ask about this lesson...'
      : 'Ask about this test...';

  Future<void> _sendSuggestion(String value) async {
    if (_busy) return;
    _question.text = value;
    setState(
      () => _suggestionOffset =
          (_suggestionOffset + 3) %
          askBayazSuggestionPool(widget.contextMaterial.kind).length,
    );
    await _send();
  }

  Future<void> _send() {
    final question = _question.text.trim();
    if (question.isEmpty || _busy || _routeLifecycle.closing || !_ready) {
      return Future<void>.value();
    }
    final token = _routeLifecycle.beginOperation();
    final operation = _sendOperation(token, question);
    _activeOperation = operation;
    return operation.whenComplete(() {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    });
  }

  Future<void> _sendOperation(int token, String question) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _lastQuestion = question;
      _messages.add(_ChatMessage(role: 'teacher', text: question));
      _question.clear();
    });
    _scrollToEnd();
    try {
      final override = widget.answerOverride;
      if (override != null) {
        final answer = await override(question);
        if (_canUpdate(token)) {
          setState(
            () => _messages.add(_ChatMessage(role: 'assistant', text: answer)),
          );
        }
        return;
      }
      final availability = await _resources.inspect();
      if (!_canUpdate(token)) return;
      final model = availability.languageModel.file;
      if (!availability.languageModel.installed || model == null) {
        setState(() {
          _ready = false;
          _readinessKnown = true;
        });
        return;
      }
      final hits = await _modelHandoff.retrieve(
        releaseGenerator: _llama.unload,
        releaseRetriever: _rag.releaseNativeModel,
        runRetrieval: () async {
          try {
            await _rag.init();
            return await _rag.retrieve(
              '${widget.contextMaterial.title}\n$question',
              k: 3,
            );
          } on FileSystemException {
            return const <Chunk>[];
          } on StateError {
            return const <Chunk>[];
          }
        },
      );
      if (!_canUpdate(token)) return;
      await _llama.loadPath(model.path, nCtx: 3072);
      if (!_canUpdate(token)) return;
      final turns = _messages
          .take(_messages.length - 1)
          .map(
            (message) =>
                ClarificationTurn(role: message.role, text: message.text),
          )
          .toList();
      final prompt = ClarificationPromptBuilder.build(
        context: widget.contextMaterial,
        question: question,
        retrieved: hits,
        history: turns,
      );
      final buffer = StringBuffer();
      final reply = _ChatMessage(role: 'assistant', text: '');
      setState(() => _messages.add(reply));
      await for (final chunk in _llama.generateChat(
        prompt.system,
        prompt.user,
      )) {
        if (!_canUpdate(token)) break;
        buffer.write(chunk);
        setState(() => reply.text = _clean(buffer.toString()));
        _scrollToEnd();
      }
      if (_canUpdate(token)) {
        setState(
          () => reply.text = _clean(buffer.toString(), finalOutput: true),
        );
      }
    } catch (error) {
      if (_canUpdate(token)) setState(() => _error = _friendlyError(error));
    } finally {
      if (_canUpdate(token)) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  bool _canUpdate(int token) => mounted && _routeLifecycle.isCurrent(token);
  Future<void> _closeAndPop() async {
    if (_routeLifecycle.closing) return;
    final close = _routeLifecycle.close(_cleanup);
    if (mounted) setState(() => _busy = true);
    await finishLocalAiRouteClose(
      close,
      description: 'closing Ask Bayaz',
      isMounted: () => mounted,
      allowPop: () => setState(() => _allowPop = true),
      pop: () => unawaited(Navigator.of(context).maybePop()),
    );
  }

  Future<void> _cleanup() async {
    try {
      await _llama.unload();
    } catch (_) {}
    final active = _activeOperation;
    if (active != null) {
      try {
        await active;
      } catch (_) {}
    }
    try {
      await _rag.dispose();
    } catch (_) {}
    if (!_localResourcesDisposed) {
      _localResourcesDisposed = true;
      _resources.dispose();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _routeLifecycle.closing || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  static String _clean(String value, {bool finalOutput = false}) =>
      GeneratedOutputSanitizer.sanitize(value, finalOutput: finalOutput);
  static String _friendlyError(Object error) =>
      error is OfflineAiDisabledException
      ? 'Offline AI is turned off in Settings.'
      : 'Bayaz couldn’t answer this question.';

  Future<void> _retry() async {
    if (!_ready) return _checkReadiness();
    final question = _lastQuestion;
    if (question == null) {
      setState(() => _error = null);
      return;
    }
    _question.text = question;
    await _send();
  }

  void _reportIssue() {
    final action = widget.onReportIssue;
    if (action != null) return action();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report issue'),
        content: const Text(
          'This build can prepare diagnostic information on this device, but no report destination is configured yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final override = widget.policyEnabledOverride;
    if (override != null) {
      return FutureBuilder<bool>(
        future: override(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.data == true ? _buildEnabled(context) : _disabled();
        },
      );
    }
    return OfflineAiGate(
      title: 'Ask Bayaz',
      policy: _offlineAiPolicy,
      enabledBuilder: _buildEnabled,
    );
  }

  Widget _disabled() => Scaffold(
    appBar: AppBar(title: const Text('Ask Bayaz')),
    body: const Center(child: Text('Offline AI is turned off in Settings.')),
  );

  Widget _buildEnabled(BuildContext context) => PopScope<void>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_closeAndPop());
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Ask Bayaz')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _contextLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Expanded(child: _mainContent()),
            if (_error != null) _errorCard(),
            if (_ready) _composer(),
          ],
        ),
      ),
    ),
  );

  Widget _mainContent() {
    if (!_readinessKnown) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 44,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Bayaz is still getting ready.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Offline AI setup is still finishing. You can try again shortly.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _checkReadiness,
                child: const Text('Try again'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ResourceManagementScreen(),
                  ),
                ),
                child: const Text('View Offline AI'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const SizedBox(height: AppSpacing.md),
          Text(
            'How can I help?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final suggestion in _suggestions) ...[
            BayazCard(
              key: const Key('ask-bayaz-suggestion'),
              onTap: () => _sendSuggestion(suggestion),
              child: Text(
                suggestion,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _messages.length + (_busy ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _MessageBubble(message: _messages[index]);
      },
    );
  }

  Widget _errorCard() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: BayazCard(
      color: Theme.of(context).colorScheme.errorContainer,
      borderColor: Theme.of(context).colorScheme.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Something went wrong',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(_error!),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonal(onPressed: _retry, child: const Text('Try again')),
          TextButton(
            onPressed: _reportIssue,
            child: const Text('Report issue'),
          ),
        ],
      ),
    ),
  );
  Widget _composer() => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _question,
            enabled: !_busy,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(hintText: _inputHint),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filled(
          tooltip: 'Send',
          onPressed: _busy ? null : _send,
          icon: const Icon(Icons.send_rounded),
        ),
      ],
    ),
  );
}

class _ChatMessage {
  _ChatMessage({required this.role, required this.text});
  final String role;
  String text;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final _ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final teacher = message.role == 'teacher';
    return Align(
      alignment: teacher ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: teacher ? AppColors.primary : AppColors.surface,
          border: teacher ? null : Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(18),
        ),
        child: SelectableText(
          message.text.isEmpty ? '…' : message.text,
          style: TextStyle(color: teacher ? Colors.white : null),
        ),
      ),
    );
  }
}
