import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_motion.dart';
import '../../design_system/theme/app_radii.dart';
import '../../design_system/theme/app_spacing.dart';
import '../chat/clarification_context.dart';
import '../chat/clarification_screen.dart';
import '../content/content_service.dart';
import '../curriculum/teaching_context.dart';
import '../export/pdf_export.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import '../resources/offline_ai_navigation.dart';
import 'lesson_plan.dart';

typedef SharePdfCallback =
    Future<bool> Function({required Uint8List bytes, required String filename});

class LessonPlanScreen extends StatefulWidget {
  const LessonPlanScreen({
    super.key,
    required this.plan,
    this.content,
    this.topic,
    this.teachingContext,
    this.initiallySaved = false,
    this.libraryStore,
    this.onSave,
    this.sharePdf,
  });

  final ContentService? content;
  final Topic? topic;
  final LessonPlan plan;
  final TeachingContext? teachingContext;
  final bool initiallySaved;
  final LibraryStore? libraryStore;
  final Future<void> Function()? onSave;
  final SharePdfCallback? sharePdf;

  @override
  State<LessonPlanScreen> createState() => _LessonPlanScreenState();
}

class _LessonPlanScreenState extends State<LessonPlanScreen> {
  late final LibraryStore _library = widget.libraryStore ?? LibraryStore();
  late LessonPlan _plan = widget.plan;
  late final Map<String, List<PlanSection>> _variants =
      widget.content != null && widget.topic != null
      ? widget.content!.variantsFor(widget.topic!.id)
      : const {};
  late bool _saved = widget.initiallySaved;
  bool _saving = false;
  bool _sharing = false;

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

  Future<void> _save({bool showMessage = true}) async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    try {
      final override = widget.onSave;
      if (override != null) {
        await override();
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;
        await _library.save(
          SavedTest(
            id: now.toString(),
            kind: 'lesson',
            source: widget.content == null
                ? SavedContentSource.customAi
                : SavedContentSource.curriculumPack,
            topic: _plan.topic,
            topicId: widget.topic?.id ?? _plan.topicId,
            createdAtMillis: now,
            contentJson: _plan.toJson(),
            teachingContext: widget.teachingContext,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _saved = true);
      if (showMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved in Bayaz')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final neededSave = !_saved;
    try {
      if (neededSave) await _save(showMessage: false);
      final bytes = await PdfExport.buildLessonPlan(
        _plan,
        teachingContext: widget.teachingContext,
      );
      final filename = 'Bayaz-${_plan.topic}-lesson-plan.pdf';
      final share =
          widget.sharePdf ??
          ({required Uint8List bytes, required String filename}) =>
              Printing.sharePdf(bytes: bytes, filename: filename);
      final shared = await share(bytes: bytes, filename: filename);
      if (!mounted) return;
      if (shared && neededSave) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Saved in Bayaz & shared')),
        );
      } else if (!shared && neededSave) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('✓ Saved in Bayaz')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_plan.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ask Bayaz',
            onPressed: () => openOfflineAiScreen(
              context,
              (_) => ClarificationScreen(
                contextMaterial: ClarificationContext.lesson(_plan),
              ),
            ),
            icon: const Icon(Icons.forum_outlined),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: LessonPlanDocument(
          plan: _plan,
          teachingContext: widget.teachingContext,
          variants: _variants,
          onCycle: _variants.isEmpty ? null : _cycle,
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(_sharing ? 'Sharing…' : 'Share'),
                ),
              ),
              if (!_saved) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save in Bayaz'),
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

class LessonPlanReadOnlyScreen extends StatelessWidget {
  const LessonPlanReadOnlyScreen({
    super.key,
    required this.plan,
    this.teachingContext,
  });

  final LessonPlan plan;
  final TeachingContext? teachingContext;

  @override
  Widget build(BuildContext context) => LessonPlanScreen(
    plan: plan,
    teachingContext: teachingContext,
    initiallySaved: true,
  );
}

class LessonPlanDocument extends StatelessWidget {
  const LessonPlanDocument({
    super.key,
    required this.plan,
    this.variants = const {},
    this.onCycle,
    this.teachingContext,
  });

  final LessonPlan plan;
  final Map<String, List<PlanSection>> variants;
  final ValueChanged<String>? onCycle;
  final TeachingContext? teachingContext;

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
        _PlanHeader(plan: plan, teachingContext: teachingContext),
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
  const _PlanHeader({required this.plan, this.teachingContext});
  final LessonPlan plan;
  final TeachingContext? teachingContext;

  @override
  Widget build(BuildContext context) {
    final teaching = [
      teachingContext?.className,
      teachingContext?.subjectName,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return BayazCard(
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
                if (teaching.isNotEmpty) const SizedBox(height: AppSpacing.xs),
                Text(
                  '${plan.totalMinutes} minutes total',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Icon(Icons.schedule_outlined, color: AppColors.primary),
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
            // A material can be a full sentence, so each one is a wrapping row
            // rather than a chip: a chip lays its label out on one unbounded
            // line and overflows the card on a narrow phone.
            for (final material in section.materials)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _SectionMaterial(material: material),
              ),
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

/// One item a teacher has to bring for a section.
///
/// The text is free-form and can run to a full sentence, so it is given the
/// whole card width and allowed to wrap onto as many lines as it needs.
class _SectionMaterial extends StatelessWidget {
  const _SectionMaterial({required this.material});

  final String material;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FC),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_box_outline_blank,
              size: 15,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              material,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
