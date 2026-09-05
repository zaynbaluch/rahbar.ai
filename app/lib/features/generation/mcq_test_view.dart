import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../chat/clarification_context.dart';
import '../chat/clarification_screen.dart';
import '../curriculum/teaching_context.dart';
import '../export/pdf_export.dart';
import '../omr/grading_screen.dart';
import '../resources/offline_ai_navigation.dart';
import '../resources/offline_ai_policy.dart';
import 'mcq_parser.dart';

typedef McqSharePdfCallback =
    Future<bool> Function({required Uint8List bytes, required String filename});
typedef OpenGradingCallback =
    Future<void> Function(
      BuildContext context,
      McqTest test,
      TeachingContext? teachingContext,
    );

class McqTestScreen extends StatelessWidget {
  const McqTestScreen({
    super.key,
    required this.test,
    this.teachingContext,
    this.onSave,
    this.saved = false,
    this.showReadyAnimation = false,
    this.sharePdf,
    this.openGrading,
    this.offlineAiPolicy,
  });

  final McqTest test;
  final TeachingContext? teachingContext;
  final Future<void> Function()? onSave;
  final bool saved;
  final bool showReadyAnimation;
  final McqSharePdfCallback? sharePdf;
  final OpenGradingCallback? openGrading;
  final OfflineAiPolicy? offlineAiPolicy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(test.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ask Bayaz',
            onPressed: () => openOfflineAiScreen(
              context,
              (_) => ClarificationScreen(
                contextMaterial: ClarificationContext.test(test),
                teachingContext: teachingContext,
              ),
              policy: offlineAiPolicy,
            ),
            icon: const Icon(Icons.forum_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          child: McqTestView(
            test: test,
            teachingContext: teachingContext,
            onSave: onSave,
            saved: saved,
            sharePdf: sharePdf,
            openGrading: openGrading,
          ),
        ),
      ),
    );
  }
}

class McqTestView extends StatefulWidget {
  const McqTestView({
    super.key,
    required this.test,
    this.teachingContext,
    this.onSave,
    this.saved = false,
    this.showReadyAnimation = false,
    this.sharePdf,
    this.openGrading,
  });

  final McqTest test;
  final TeachingContext? teachingContext;
  final Future<void> Function()? onSave;
  final bool saved;
  final bool showReadyAnimation;
  final McqSharePdfCallback? sharePdf;
  final OpenGradingCallback? openGrading;

  @override
  State<McqTestView> createState() => _McqTestViewState();
}

class _McqTestViewState extends State<McqTestView> {
  bool _showAnswers = false;
  bool _saving = false;
  bool _sharing = false;
  bool _openingGrading = false;
  late bool _saved = widget.saved;

  @override
  void didUpdateWidget(covariant McqTestView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.saved != widget.saved) _saved = widget.saved;
  }

  Future<bool> _ensureSaved({bool showMessage = false}) async {
    if (_saved) return true;
    final save = widget.onSave;
    if (save == null || _saving) return false;
    setState(() => _saving = true);
    try {
      await save();
      if (!mounted) return true;
      setState(() => _saved = true);
      if (showMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved in Bayaz')));
      }
      return true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing || !widget.test.isReady) return;
    setState(() => _sharing = true);
    final neededSave = !_saved;
    try {
      if (!await _ensureSaved()) return;
      final bytes = await PdfExport.build(
        widget.test,
        teachingContext: widget.teachingContext,
      );
      final filename = 'Bayaz-${PdfExport.testId(widget.test)}.pdf';
      final share =
          widget.sharePdf ??
          ({required Uint8List bytes, required String filename}) =>
              Printing.sharePdf(bytes: bytes, filename: filename);
      final shared = await share(bytes: bytes, filename: filename);
      if (!mounted || !neededSave) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared ? '✓ Saved in Bayaz & shared' : '✓ Saved in Bayaz',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _grade() async {
    if (_openingGrading || !widget.test.isReady) return;
    setState(() => _openingGrading = true);
    try {
      if (!await _ensureSaved()) return;
      if (!mounted) return;
      final open = widget.openGrading;
      if (open != null) {
        await open(context, widget.test, widget.teachingContext);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GradingScreen(
              test: widget.test,
              teachingContext: widget.teachingContext,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingGrading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teaching = [
      widget.teachingContext?.className,
      widget.teachingContext?.subjectName,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayazCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (teaching.isNotEmpty)
                      Text(
                        teaching,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    if (teaching.isNotEmpty)
                      const SizedBox(height: AppSpacing.xs),
                    Text('${widget.test.count} questions'),
                  ],
                ),
              ),
              const Icon(Icons.quiz_outlined, color: AppColors.primary),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sharing || !widget.test.isReady ? null : _share,
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(_sharing ? 'Sharing…' : 'Share'),
              ),
            ),
            if (!_saved) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving || widget.onSave == null
                      ? null
                      : () => _ensureSaved(showMessage: true),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save in Bayaz'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openingGrading || !widget.test.isReady
                    ? null
                    : _grade,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Grade sheets'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextButton.icon(
                onPressed: () => setState(() => _showAnswers = !_showAnswers),
                icon: Icon(
                  _showAnswers
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                label: Text(_showAnswers ? 'Hide answers' : 'Show answers'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final question in widget.test.questions) ...[
          _QuestionCard(question: question, showAnswer: _showAnswers),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.showAnswer});

  final McqQuestion question;
  final bool showAnswer;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.softBlue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${question.number}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: AppColors.primary),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  question.text.isEmpty
                      ? '(Missing question text)'
                      : question.text,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final letter in const ['A', 'B', 'C', 'D'])
            if (question.options.containsKey(letter)) ...[
              _OptionRow(
                letter: letter,
                text: question.options[letter]!,
                correct: showAnswer && question.answer == letter,
              ),
              const SizedBox(height: 6),
            ],
        ],
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: correct ? const Color(0xFFDDF5E8) : const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: correct ? AppColors.success : AppColors.outline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: correct ? AppColors.success : AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: correct ? AppColors.success : AppColors.primaryMedium,
              ),
            ),
            child: Text(
              letter,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: correct ? Colors.white : AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          if (correct)
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 21,
            ),
        ],
      ),
    );
  }
}
