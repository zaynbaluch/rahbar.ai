import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../design_system/components/frame_animation.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../chat/clarification_context.dart';
import '../chat/clarification_screen.dart';
import '../export/pdf_export.dart';
import '../omr/grading_screen.dart';
import 'mcq_parser.dart';

class McqTestScreen extends StatelessWidget {
  const McqTestScreen({
    super.key,
    required this.test,
    this.onSave,
    this.saved = false,
    this.showReadyAnimation = false,
  });

  final McqTest test;
  final Future<void> Function()? onSave;
  final bool saved;
  final bool showReadyAnimation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(test.topic,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ask about this test',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ClarificationScreen(
                contextMaterial: ClarificationContext.test(test),
              ),
            )),
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
            onSave: onSave,
            saved: saved,
            showReadyAnimation: showReadyAnimation,
          ),
        ),
      ),
    );
  }
}

/// Reusable structured paper review. It exposes only actions already implemented:
/// save, print/export, reveal the teacher key, and grade this exact paper.
class McqTestView extends StatefulWidget {
  const McqTestView({
    super.key,
    required this.test,
    this.onSave,
    this.saved = false,
    this.showReadyAnimation = false,
  });

  final McqTest test;
  final Future<void> Function()? onSave;
  final bool saved;
  final bool showReadyAnimation;

  @override
  State<McqTestView> createState() => _McqTestViewState();
}

class _McqTestViewState extends State<McqTestView> {
  bool _showAnswers = false;
  bool _saving = false;
  bool _exporting = false;
  late bool _saved = widget.saved;

  @override
  void didUpdateWidget(covariant McqTestView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.saved != widget.saved) _saved = widget.saved;
  }

  Future<void> _save() async {
    final action = widget.onSave;
    if (action == null || _saved || _saving) return;
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) setState(() => _saved = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await PdfExport.build(widget.test);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Bayaz-${PdfExport.testId(widget.test)}',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final test = widget.test;
    final ready = test.isReady;
    final counts = <String, int>{};
    for (final question in test.questions) {
      final key = question.difficulty.isEmpty ? 'unspecified' : question.difficulty;
      counts[key] = (counts[key] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(
          test: test,
          counts: counts,
          showAnimation: widget.showReadyAnimation,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ActionBar(
          showAnswers: _showAnswers,
          saved: _saved,
          saving: _saving,
          exporting: _exporting,
          onSave: widget.onSave == null || !ready ? null : _save,
          onToggle: () => setState(() => _showAnswers = !_showAnswers),
          onExport: ready ? _export : null,
          onGrade: ready
              ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GradingScreen(test: test),
                  ))
              : null,
          onClarify: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ClarificationScreen(
              contextMaterial: ClarificationContext.test(test),
            ),
          )),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Questions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        for (final question in test.questions) ...[
          _QuestionCard(question: question, showAnswer: _showAnswers),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.test,
    required this.counts,
    required this.showAnimation,
  });

  final McqTest test;
  final Map<String, int> counts;
  final bool showAnimation;

  @override
  Widget build(BuildContext context) {
    final validation = test.validation;
    final complete = validation.isReady;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complete ? 'Paper ready' : 'Paper needs review',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${test.count} of ${test.expectedCount} questions · ID ${test.id}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                ),
                if (!complete) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    validation.summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final entry in counts.entries)
                      _SummaryPill(
                        label: '${entry.value} ${entry.key}',
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          showAnimation
              ? const BayazFrameAnimation(
                  name: 'test_ready',
                  size: 112,
                )
              : Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    complete ? Icons.fact_check_rounded : Icons.rule_rounded,
                    color: AppColors.gold,
                    size: 38,
                  ),
                ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.showAnswers,
    required this.saved,
    required this.saving,
    required this.exporting,
    required this.onSave,
    required this.onToggle,
    required this.onExport,
    required this.onGrade,
    required this.onClarify,
  });

  final bool showAnswers;
  final bool saved;
  final bool saving;
  final bool exporting;
  final VoidCallback? onSave;
  final VoidCallback onToggle;
  final VoidCallback? onExport;
  final VoidCallback? onGrade;
  final VoidCallback onClarify;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          if (onSave != null)
            FilledButton.tonalIcon(
              onPressed: saved || saving ? null : onSave,
              icon: Icon(saved
                  ? Icons.bookmark_added_rounded
                  : Icons.bookmark_add_outlined),
              label: Text(saved ? 'Saved' : (saving ? 'Saving…' : 'Save')),
            ),
          OutlinedButton.icon(
            onPressed: exporting ? null : onExport,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(exporting ? 'Preparing…' : 'Print / PDF'),
          ),
          OutlinedButton.icon(
            onPressed: onGrade,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Grade sheets'),
          ),
          OutlinedButton.icon(
            onPressed: onClarify,
            icon: const Icon(Icons.forum_outlined),
            label: const Text('Ask Bayaz'),
          ),
          TextButton.icon(
            onPressed: onToggle,
            icon: Icon(showAnswers
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            label: Text(showAnswers ? 'Hide teacher key' : 'Show teacher key'),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.showAnswer});

  final McqQuestion question;
  final bool showAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  question.text.isEmpty
                      ? '(Missing question text)'
                      : question.text,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (question.difficulty.isNotEmpty)
                StatusChip(label: question.difficulty),
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
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 21),
        ],
      ),
    );
  }
}
