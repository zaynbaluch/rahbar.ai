import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../generation/generation_screen.dart';
import '../generation/lesson_plan_view.dart';
import '../generation/mcq_parser.dart';
import '../generation/mcq_test_view.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import 'content_service.dart';

/// Existing topic workspace: lesson-plan assembly and MCQ-paper sampling.
class TopicScreen extends StatefulWidget {
  const TopicScreen({super.key, required this.content, required this.topic});

  final ContentService content;
  final Topic topic;

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  final _library = LibraryStore();
  bool _openingTest = false;

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    return Scaffold(
      appBar: AppBar(title: const Text('Topic workspace')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            _TopicHeader(topic: topic),
            const SizedBox(height: AppSpacing.lg),
            if (topic.slos.isNotEmpty) ...[
              _LearningOutcomes(slos: topic.slos),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text('What do you need?',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            _TaskCard(
              image: 'assets/ui/illustrations/create_lesson_plan.webp',
              title: 'Prepare a lesson plan',
              description:
                  'Assemble a structured 50-minute plan and swap individual activity variants instantly.',
              buttonLabel: 'Open lesson plan',
              icon: Icons.menu_book_outlined,
              onPressed: _openPlan,
            ),
            const SizedBox(height: AppSpacing.sm),
            _TaskCard(
              image: 'assets/ui/illustrations/create_mcq_test.webp',
              title: 'Create an MCQ paper',
              description: topic.hasTest
                  ? 'Draw a fresh paper from ${topic.nItems} verified questions, then save, print, or grade it.'
                  : 'This topic currently has ${topic.nItems} verified questions, so the paper may contain fewer than 10 questions.',
              buttonLabel: _openingTest ? 'Preparing…' : 'Create paper',
              icon: Icons.fact_check_outlined,
              enabled: topic.nItems > 0 && !_openingTest,
              accent: true,
              onPressed: _openTest,
            ),
            if (!topic.hasTest && topic.nItems > 0) ...[
              const SizedBox(height: AppSpacing.sm),
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
                        'Bayaz will use every currently available verified question. It will not invent missing items or imply that a 10-question paper exists.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.warningText,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text('Need something different?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Custom offline AI is optional and slower than the verified curriculum content. It may take 4–5 minutes and must be reviewed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openCustom('lesson'),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Custom lesson'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openCustom('mcq'),
                    icon: const Icon(Icons.quiz_outlined),
                    label: const Text('Custom MCQs'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openCustom(String kind) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GenerationScreen(
        initialTopic: widget.topic.title,
        initialKind: kind,
      ),
    ));
  }

  void _openPlan() {
    final plan = widget.content.assemblePlan(widget.topic.id);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LessonPlanScreen(
        content: widget.content,
        topic: widget.topic,
        plan: plan,
      ),
    ));
  }

  Future<void> _openTest() async {
    if (_openingTest) return;
    setState(() => _openingTest = true);
    try {
      final used = await _usedItemIds(widget.topic.id);
      if (!mounted) return;
      McqTest test;
      try {
        test = widget.content.sampleTest(widget.topic.id, exclude: used);
      } on InsufficientUnusedItemsException catch (shortage) {
        final reuse = await _confirmReuse(shortage);
        if (reuse != true || !mounted) return;
        test = widget.content.sampleTest(
          widget.topic.id,
          exclude: used,
          allowReuse: true,
        );
      }
      await _presentTest(test);
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _openingTest = false);
    }
  }

  Future<bool?> _confirmReuse(InsufficientUnusedItemsException shortage) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some questions will repeat'),
          content: Text(
            'Only ${shortage.availableUnused} unused verified questions remain. '
            'A ${shortage.required}-question paper needs ${shortage.reuseCount} '
            'previously used question${shortage.reuseCount == 1 ? '' : 's'}. '
            'Bayaz will still reshuffle safe answer positions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create with repeats'),
            ),
          ],
        ),
      );

  Future<void> _presentTest(McqTest test) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => McqTestScreen(
        test: test,
        showReadyAnimation: true,
        onSave: () => _saveTest(test),
      ),
    ));
  }

  Future<Set<String>> _usedItemIds(String topicId) async {
    final saved = await _library.list();
    final used = <String>{};
    for (final item in saved) {
      if (item.kind == 'mcq' &&
          item.topicId == topicId &&
          item.contentJson != null) {
        used.addAll(item.toMcqTest().itemIds);
      }
    }
    return used;
  }

  Future<void> _saveTest(McqTest test) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _library.save(SavedTest(
      id: test.id,
      kind: 'mcq',
      topic: widget.topic.title,
      topicId: widget.topic.id,
      createdAtMillis: now,
      contentJson: test.toJson(),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Library')),
      );
    }
  }
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.topic});
  final Topic topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _HeaderPill(label: 'Chapter ${topic.chapter}'),
              _HeaderPill(label: 'Section ${topic.sectionNo}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            topic.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                ),
          ),
          if (topic.summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              topic.summary,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          StatusChip(
            label: '${topic.nItems} verified MCQs available',
            icon: Icons.verified_outlined,
            backgroundColor: Colors.white.withValues(alpha: 0.14),
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

class _LearningOutcomes extends StatelessWidget {
  const _LearningOutcomes({required this.slos});
  final List<String> slos;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.track_changes_outlined,
                  color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Text('Learning outcomes',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final outcome in slos) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Icon(Icons.circle,
                      size: 6, color: AppColors.primaryMedium),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(outcome)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.image,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.accent = false,
  });

  final String image;
  final String title;
  final String description;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: compact ? double.infinity : null,
                child: accent
                    ? FilledButton.icon(
                        onPressed: enabled ? onPressed : null,
                        icon: Icon(icon),
                        label: Text(buttonLabel),
                      )
                    : OutlinedButton.icon(
                        onPressed: enabled ? onPressed : null,
                        icon: Icon(icon),
                        label: Text(buttonLabel),
                      ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Image.asset(image, height: 132),
                ),
                const SizedBox(height: AppSpacing.sm),
                text,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: AppSpacing.md),
              Image.asset(image, width: 145, height: 145),
            ],
          );
        },
      ),
    );
  }
}
