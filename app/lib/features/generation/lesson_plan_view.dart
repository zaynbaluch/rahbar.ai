import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_motion.dart';
import '../../design_system/theme/app_spacing.dart';
import '../chat/clarification_context.dart';
import '../chat/clarification_screen.dart';
import '../content/content_service.dart';
import '../export/pdf_export.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import 'lesson_plan.dart';

class LessonPlanScreen extends StatefulWidget {
  const LessonPlanScreen({
    super.key,
    required this.content,
    required this.topic,
    required this.plan,
  });

  final ContentService content;
  final Topic topic;
  final LessonPlan plan;

  @override
  State<LessonPlanScreen> createState() => _LessonPlanScreenState();
}

class _LessonPlanScreenState extends State<LessonPlanScreen> {
  final _library = LibraryStore();
  late LessonPlan _plan = widget.plan;
  late final Map<String, List<PlanSection>> _variants = widget.content
      .variantsFor(widget.topic.id);
  bool _saved = false;
  bool _saving = false;
  bool _printing = false;

  void _cycle(String section) {
    final options = _variants[section];
    if (options == null || options.length < 2) return;
    final current = _plan.sectionOf(section);
    final index = options.indexWhere((variant) => variant.id == current?.id);
    final next = options[(index + 1) % options.length];
    setState(() {
      _plan = LessonPlan(
        topicId: _plan.topicId,
        topic: _plan.topic,
        slos: _plan.slos,
        sections: [
          for (final item in _plan.sections)
            item.section == section ? next : item,
        ],
      );
      _saved = false;
    });
  }

  Future<void> _save() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _library.save(
        SavedTest(
          id: now.toString(),
          kind: 'lesson',
          topic: _plan.topic,
          topicId: _plan.topicId,
          createdAtMillis: now,
          contentJson: _plan.toJson(),
        ),
      );
      if (mounted) {
        setState(() => _saved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lesson plan saved to Library')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        onLayout: (_) => PdfExport.buildLessonPlan(_plan),
        name: 'Bayaz-${_plan.topic}-lesson-plan',
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_plan.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ask about this lesson',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ClarificationScreen(
                contextMaterial: ClarificationContext.lesson(_plan),
              ),
            )),
            icon: const Icon(Icons.forum_outlined),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: LessonPlanDocument(
          plan: _plan,
          variants: _variants,
          onCycle: _cycle,
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _printing ? null : _print,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(_printing ? 'Preparing…' : 'Print / PDF'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saved || _saving ? null : _save,
                  icon: Icon(
                    _saved
                        ? Icons.bookmark_added_rounded
                        : Icons.bookmark_add_outlined,
                  ),
                  label: Text(
                    _saved ? 'Saved' : (_saving ? 'Saving…' : 'Save plan'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LessonPlanReadOnlyScreen extends StatelessWidget {
  const LessonPlanReadOnlyScreen({super.key, required this.plan});

  final LessonPlan plan;

  Future<void> _print() => Printing.layoutPdf(
    onLayout: (_) => PdfExport.buildLessonPlan(plan),
    name: 'Bayaz-${plan.topic}-lesson-plan',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(plan.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ask about this lesson',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ClarificationScreen(
                contextMaterial: ClarificationContext.lesson(plan),
              ),
            )),
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: 'Print or export PDF',
            onPressed: _print,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: SafeArea(child: LessonPlanDocument(plan: plan)),
    );
  }
}

class LessonPlanDocument extends StatelessWidget {
  const LessonPlanDocument({
    super.key,
    required this.plan,
    this.variants = const {},
    this.onCycle,
  });

  final LessonPlan plan;
  final Map<String, List<PlanSection>> variants;
  final ValueChanged<String>? onCycle;

  @override
  Widget build(BuildContext context) {
    final materials = plan.materials;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        _PlanHeader(plan: plan),
        const SizedBox(height: AppSpacing.md),
        if (plan.slos.isNotEmpty) ...[
          _OutcomeCard(slos: plan.slos),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (materials.isNotEmpty) ...[
          _MaterialsCard(materials: materials),
          const SizedBox(height: AppSpacing.lg),
        ] else
          const SizedBox(height: AppSpacing.sm),
        Text('Lesson sequence', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        for (final section in plan.sections) ...[
          _SectionCard(
            section: section,
            options: variants[section.section] ?? const [],
            onCycle: onCycle,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.plan});
  final LessonPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '50-minute lesson plan',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Grade 6 · General Science · structured around the 5E sequence',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                StatusChip(
                  label: '${plan.totalMinutes} minutes total',
                  icon: Icons.schedule_outlined,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  foregroundColor: Colors.white,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Image.asset(
            'assets/ui/illustrations/create_lesson_plan.webp',
            width: 104,
            height: 104,
          ),
        ],
      ),
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.slos});
  final List<String> slos;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: AppSpacing.xs),
        leading: const Icon(
          Icons.track_changes_outlined,
          color: AppColors.primary,
        ),
        title: const Text('Learning outcomes'),
        subtitle: Text('${slos.length} outcomes'),
        children: [
          for (final outcome in slos)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.primaryMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(outcome)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MaterialsCard extends StatelessWidget {
  const _MaterialsCard({required this.materials});
  final List<String> materials;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      color: AppColors.softGold,
      borderColor: const Color(0xFFFFD96A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.warningText,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'What to bring',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: AppColors.warningText),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            materials.join(' · '),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.warningText),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.options,
    this.onCycle,
  });

  final PlanSection section;
  final List<PlanSection> options;
  final ValueChanged<String>? onCycle;

  @override
  Widget build(BuildContext context) {
    final canSwap = onCycle != null && options.length > 1;
    return AnimatedSwitcher(
      duration: AppMotion.standard,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      child: BayazCard(
        key: ValueKey(section.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.softBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _sectionIcon(section.section),
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LessonPlan.sectionTitles[section.section] ??
                            section.section,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (canSwap && section.variantLabel.isNotEmpty)
                        Text(
                          section.variantLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (section.minutes > 0)
                  StatusChip(
                    label: '${section.minutes} min',
                    icon: Icons.schedule_outlined,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(section.body),
            if (section.materials.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final material in section.materials)
                    StatusChip(
                      label: material,
                      icon: Icons.check_box_outline_blank,
                      backgroundColor: const Color(0xFFF0F4FC),
                      foregroundColor: AppColors.textSecondary,
                    ),
                ],
              ),
            ],
            if (canSwap) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => onCycle!(section.section),
                  icon: const Icon(Icons.autorenew_rounded),
                  label: Text('Try another (${options.length} available)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _sectionIcon(String section) => switch (section) {
    'objectives' => Icons.flag_outlined,
    'revision_starter' => Icons.refresh_rounded,
    'engage' => Icons.lightbulb_outline_rounded,
    'explore' => Icons.science_outlined,
    'explain' => Icons.record_voice_over_outlined,
    'socratic' => Icons.question_answer_outlined,
    'elaborate' => Icons.account_tree_outlined,
    'evaluate' => Icons.fact_check_outlined,
    'differentiation' => Icons.groups_outlined,
    'homework' => Icons.home_work_outlined,
    'notes' => Icons.sticky_note_2_outlined,
    _ => Icons.circle_outlined,
  };
}
