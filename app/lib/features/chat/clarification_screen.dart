import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
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

class ClarificationScreen extends StatefulWidget {
  const ClarificationScreen({
    super.key,
    required this.contextMaterial,
    this.offlineAiPolicy,
  });

  final ClarificationContext contextMaterial;
  final OfflineAiPolicy? offlineAiPolicy;

  @override
  State<ClarificationScreen> createState() => _ClarificationScreenState();
}

class _ClarificationScreenState extends State<ClarificationScreen> {
  final _question = TextEditingController();
  final _scroll = ScrollController();
  final _rag = RagService();
  final _llama = LlamaCppService();
  final _modelHandoff = const LocalModelHandoff();
  final _routeLifecycle = LocalAiRouteLifecycle();
  final _resources = LocalAiResources();
  late final OfflineAiPolicy _offlineAiPolicy;
  final _messages = <_ChatMessage>[];

  @override
  void initState() {
    super.initState();
    _offlineAiPolicy = widget.offlineAiPolicy ?? OfflineAiPolicy();
  }

  bool _busy = false;
  bool _grounded = false;
  bool _modelMissing = false;
  String? _error;
  String _phase = '';
  Future<void>? _activeOperation;
  bool _allowPop = false;
  bool _localResourcesDisposed = false;

  @override
  void dispose() {
    _routeLifecycle.cancelOperations();
    _question.dispose();
    _scroll.dispose();
    unawaited(_routeLifecycle.close(_cleanup));
    super.dispose();
  }

  Future<void> _send() {
    final question = _question.text.trim();
    if (question.isEmpty || _busy || _routeLifecycle.closing) {
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
      _modelMissing = false;
      _grounded = false;
      _phase = 'Checking offline AI…';
    });

    try {
      await _offlineAiPolicy.requireEnabled();
      if (!_canUpdate(token)) return;
      setState(() {
        _messages.add(_ChatMessage(role: 'teacher', text: question));
        _question.clear();
      });
      _scrollToEnd();
      final availability = await _resources.inspect();
      if (!_canUpdate(token)) return;
      final model = availability.languageModel.file;
      if (!availability.languageModel.installed || model == null) {
        if (_canUpdate(token)) {
          setState(() {
            _modelMissing = true;
            _phase = '';
          });
        }
        return;
      }

      if (_canUpdate(token)) {
        setState(() => _phase = 'Finding relevant curriculum…');
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
      _grounded = hits.isNotEmpty;

      setState(() => _phase = 'Loading the local model…');
      await _llama.loadPath(model.path, nCtx: 3072);
      if (!_canUpdate(token)) return;
      final turns = _messages
          .take(_messages.length - 1)
          .map((message) => ClarificationTurn(
                role: message.role,
                text: message.text,
              ))
          .toList();
      final prompt = ClarificationPromptBuilder.build(
        context: widget.contextMaterial,
        question: question,
        retrieved: hits,
        history: turns,
      );

      setState(() => _phase = 'Writing the answer…');
      final buffer = StringBuffer();
      final reply = _ChatMessage(
        role: 'assistant',
        text: '',
        grounded: _grounded,
      );
      setState(() => _messages.add(reply));
      await for (final chunk in _llama.generateChat(prompt.system, prompt.user)) {
        if (!_canUpdate(token)) break;
        buffer.write(chunk);
        setState(() => reply.text = _clean(buffer.toString()));
        _scrollToEnd();
      }
      if (_canUpdate(token)) {
        setState(() => reply.text = _clean(
              buffer.toString(),
              finalOutput: true,
            ));
      }
    } catch (error) {
      if (_canUpdate(token)) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (_canUpdate(token)) {
        setState(() {
          _busy = false;
          _phase = '';
        });
      }
      _scrollToEnd();
    }
  }

  bool _canUpdate(int token) => mounted && _routeLifecycle.isCurrent(token);

  Future<void> _closeAndPop() async {
    if (_routeLifecycle.closing) return;
    final close = _routeLifecycle.close(_cleanup);
    if (mounted) {
      setState(() {
        _busy = true;
        _phase = 'Closing offline AI safely…';
      });
    }
    await finishLocalAiRouteClose(
      close,
      description: 'closing the clarification screen',
      isMounted: () => mounted,
      allowPop: () => setState(() => _allowPop = true),
      pop: () => unawaited(Navigator.of(context).maybePop()),
    );
  }

  Future<void> _cleanup() async {
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
      _resources.dispose();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _routeLifecycle.closing) return;
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  static String _clean(String value, {bool finalOutput = false}) =>
      GeneratedOutputSanitizer.sanitize(
        value,
        finalOutput: finalOutput,
      );

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (error is OfflineAiDisabledException) {
      return 'Offline AI is turned off. Enable it in teacher setup before asking a question.';
    }
    if (text.contains('not installed') || text.contains('No such file')) {
      return 'Offline AI is not installed or is incomplete. Open AI setup and verify the model files.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) => OfflineAiGate(
        title: widget.contextMaterial.kind == 'general'
            ? 'Ask Bayaz'
            : 'Clarify ${widget.contextMaterial.title}',
        policy: _offlineAiPolicy,
        enabledBuilder: _buildEnabled,
      );

  Widget _buildEnabled(BuildContext context) {
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeAndPop());
      },
      child: Scaffold(
        appBar: AppBar(
        title: Text(
          widget.contextMaterial.kind == 'general'
              ? 'Ask Bayaz'
              : 'Clarify ${widget.contextMaterial.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
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
              child: BayazCard(
                color: AppColors.softGold,
                borderColor: const Color(0xFFFFD96A),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.offline_bolt_outlined,
                        color: AppColors.warningText),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.contextMaterial.kind == 'general'
                            ? 'Answers run on this device. Bayaz retrieves only a few relevant curriculum excerpts and keeps a short conversation window.'
                            : 'The current ${widget.contextMaterial.kind} is included in a compact context. Check factual answers before classroom use.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.warningText,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyChat(kind: widget.contextMaterial.kind)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) => _MessageBubble(
                        message: _messages[index],
                      ),
                    ),
            ),
            if (_modelMissing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: BayazCard(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderColor: Theme.of(context).colorScheme.error,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'The language model is not installed. Chat cannot answer without it.',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ResourceManagementScreen(
                              setupMode: true,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Open offline AI setup'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_phase.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  0,
                ),
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(_phase),
                  ],
                ),
              ),
            Padding(
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
                      decoration: const InputDecoration(
                        hintText: 'Ask a teaching question',
                        prefixIcon: Icon(Icons.help_outline_rounded),
                      ),
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
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  _ChatMessage({
    required this.role,
    required this.text,
    this.grounded,
  });

  final String role;
  String text;
  final bool? grounded;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text.isEmpty ? '…' : message.text,
              style: TextStyle(color: teacher ? Colors.white : null),
            ),
            if (!teacher && message.grounded != null) ...[
              const SizedBox(height: AppSpacing.xs),
              StatusChip(
                label: message.grounded!
                    ? 'Curriculum-grounded'
                    : 'Ungrounded - verify facts',
                icon: message.grounded!
                    ? Icons.menu_book_outlined
                    : Icons.warning_amber_rounded,
                backgroundColor: message.grounded!
                    ? const Color(0xFFDDF5E8)
                    : AppColors.softGold,
                foregroundColor: message.grounded!
                    ? AppColors.success
                    : AppColors.warningText,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final prompts = kind == 'lesson'
        ? const [
            'How can I explain the hardest idea more simply?',
            'What should I do if the activity finishes early?',
            'Give me one low-cost alternative material.',
          ]
        : kind == 'test'
            ? const [
                'Explain why question 3 has that answer.',
                'Which misconceptions does this paper check?',
                'How can I reteach the weakest topic?',
              ]
            : const [
                'How can I teach this concept with no lab equipment?',
                'Give me a five-minute revision activity.',
                'Explain this topic in simpler classroom language.',
              ];
    return Center(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const Icon(Icons.forum_outlined, size: 52, color: AppColors.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ask a focused question',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final prompt in prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text('• $prompt', textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}
