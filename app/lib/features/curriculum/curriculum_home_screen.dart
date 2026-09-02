import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/brand_app_bar.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../content/topic_picker_screen.dart';
import '../library/library_screen.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import '../omr/grade_papers_screen.dart';
import '../omr/gradebook_store.dart';
import '../omr/graded_result.dart';
import '../omr/grading_screen.dart';
import '../omr/results_screen.dart';
import 'teaching_context.dart';
import 'recent_work_store.dart';
import 'teaching_context_selector.dart';
import 'workflow_context_resolver.dart';
import 'workflow_context_store.dart';
import '../onboarding/onboarding_store.dart';
import '../resources/background_ai_download_controller.dart';
import '../settings/settings_screen.dart';
import 'curriculum_catalog.dart';

Future<void> launchTeacherWorkflow(
  BuildContext context,
  TopicPickerMode mode, {
  OnboardingStore? onboardingStore,
  WorkflowContextStore? workflowContextStore,
  RecentWorkStore? recentWorkStore,
}) async {
  final onboarding = onboardingStore ?? OnboardingStore();
  final workflowContexts = workflowContextStore ?? WorkflowContextStore();
  final recentWork = recentWorkStore ?? RecentWorkStore();
  await recentWork.clearActiveGrading();
  final state = await onboarding.read();
  final workflowKey = mode == TopicPickerMode.lesson ? 'lesson' : 'test';
  final last = await workflowContexts.lastFor(workflowKey);
  final resolution = WorkflowContextResolver.resolve(
    state: state,
    classes: CurriculumCatalog.classes,
    last: last,
  );
  if (!context.mounted) return;

  TeachingContext? selected = resolution.context;
  if (resolution.needsSelector) {
    final selectedClasses = CurriculumCatalog.classes
        .where((item) => state.selectedClasses.contains(item.code))
        .toList(growable: false);
    selected = await showTeachingContextSelector(
      context,
      classes: selectedClasses,
      selectedSubjectsByClass: state.selectedSubjectsByClass,
      initial: last,
    );
    if (selected == null || !context.mounted) return;
    await workflowContexts.save(workflowKey, selected);
  }
  if (!context.mounted) return;
  if (selected == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Choose a class and subject in Settings first.'),
      ),
    );
    return;
  }
  if (resolution.context != null) {
    await workflowContexts.save(workflowKey, selected);
    if (!context.mounted) return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TopicPickerScreen(
        mode: mode,
        teachingContext: selected!,
        showContextChange: resolution.showContextChange,
        onboardingStore: onboarding,
        workflowContextStore: workflowContexts,
      ),
    ),
  );
}

class CurriculumHomeScreen extends StatefulWidget {
  const CurriculumHomeScreen({
    super.key,
    this.backgroundAiController,
    this.onboardingStore,
    this.onPrepareLesson,
    this.onCreateTest,
    this.onGradePapers,
    this.onContinueRecent,
    this.openSettings,
    this.recentWorkStore,
    this.libraryStore,
    this.gradebookStore,
    this.onOpenMyWork,
  });

  final BackgroundAiDownloadController? backgroundAiController;
  final OnboardingStore? onboardingStore;
  final VoidCallback? onPrepareLesson;
  final VoidCallback? onCreateTest;
  final VoidCallback? onGradePapers;
  final VoidCallback? onContinueRecent;
  final Future<void> Function(BuildContext context)? openSettings;
  final RecentWorkStore? recentWorkStore;
  final LibraryStore? libraryStore;
  final GradebookStore? gradebookStore;
  final VoidCallback? onOpenMyWork;

  @override
  State<CurriculumHomeScreen> createState() => _CurriculumHomeScreenState();
}

class _CurriculumHomeScreenState extends State<CurriculumHomeScreen> {
  late final OnboardingStore _onboardingStore;
  late Future<OnboardingState> _teacher;
  late final WorkflowContextStore _workflowContexts;
  late final RecentWorkStore _recentWork;
  late final LibraryStore _library;
  late final GradebookStore _gradebook;
  late Future<_ContinueRecentTarget> _recentTarget;
  bool _downloadCardDismissed = false;

  @override
  void initState() {
    super.initState();
    _onboardingStore = widget.onboardingStore ?? OnboardingStore();
    _workflowContexts = WorkflowContextStore();
    _recentWork = widget.recentWorkStore ?? RecentWorkStore();
    _library = widget.libraryStore ?? LibraryStore();
    _gradebook = widget.gradebookStore ?? GradebookStore();
    _teacher = _onboardingStore.read();
    _recentTarget = _loadRecentTarget();
  }

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final tiles = _homeTiles();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Tooltip(
          message: 'Open Settings',
          child: Semantics(
            button: true,
            label: 'Open Settings',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _openSettings,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: BrandAppBarTitle(),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (largeText)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _homeHero(),
                        const SizedBox(height: AppSpacing.xl),
                        for (var i = 0; i < tiles.length; i++) ...[
                          SizedBox(height: 220, child: tiles[i]),
                          if (i < tiles.length - 1)
                            const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                )
              else ...[
                Expanded(flex: 4, child: _homeHero()),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: tiles[0]),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: tiles[1]),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: tiles[2]),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: tiles[3]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.backgroundAiController != null)
                StreamBuilder<BackgroundAiDownloadState>(
                  stream: widget.backgroundAiController!.stream,
                  initialData: widget.backgroundAiController!.state,
                  builder: (context, snapshot) =>
                      _downloadStatus(snapshot.data!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeHero() => FutureBuilder<OnboardingState>(
    future: _teacher,
    builder: (context, snapshot) {
      final name = snapshot.data?.teacherName.trim() ?? '';
      return Align(
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? 'السلام علیکم' : 'السلام علیکم، $name',
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'آج کیا تیار کرنا ہے؟',
              textDirection: TextDirection.rtl,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    },
  );

  List<Widget> _homeTiles() => [
    _ActionTile(
      icon: Icons.menu_book_outlined,
      label: 'Prepare Lesson',
      onTap:
          widget.onPrepareLesson ?? () => _openWorkflow(TopicPickerMode.lesson),
    ),
    _ActionTile(
      icon: Icons.quiz_outlined,
      label: 'Create Test',
      onTap: widget.onCreateTest ?? () => _openWorkflow(TopicPickerMode.test),
    ),
    _ActionTile(
      icon: Icons.camera_alt_outlined,
      label: 'Grade Papers',
      onTap: widget.onGradePapers ?? _openGradePapers,
    ),
    FutureBuilder<_ContinueRecentTarget>(
      future: _recentTarget,
      builder: (context, snapshot) {
        final target = snapshot.data ?? const _ContinueRecentTarget.fallback();
        return _ActionTile(
          icon: Icons.refresh_rounded,
          label: target.actionLabel,
          subtitle: target.subtitle,
          onTap: () => _continueRecent(target),
        );
      },
    ),
  ];

  Widget _downloadStatus(BackgroundAiDownloadState state) {
    if (state.completed || (!state.running && !state.needsAttention)) {
      return const SizedBox.shrink();
    }
    if (state.needsAttention) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Card(
          elevation: 5,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Offline AI needs attention',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text('Bayaz could not finish setting up offline AI.'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    FilledButton.tonal(
                      onPressed: widget.backgroundAiController!.retry,
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: _openSettings,
                      child: const Text('Settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_downloadCardDismissed) return const SizedBox.shrink();
    final progress = state.progress;
    final percent = progress == null ? null : (progress * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Card(
        elevation: 5,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Preparing offline AI',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hide download progress',
                    onPressed: () =>
                        setState(() => _downloadCardDismissed = true),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: AppSpacing.xs),
              Text(
                percent == null
                    ? 'You can keep using Bayaz.'
                    : '$percent% · You can keep using Bayaz.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final override = widget.openSettings;
    if (override != null) {
      await override(context);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SettingsScreen(downloadController: widget.backgroundAiController),
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _teacher = _onboardingStore.read();
    });
  }

  Future<void> _openWorkflow(TopicPickerMode mode) async {
    await launchTeacherWorkflow(
      context,
      mode,
      onboardingStore: _onboardingStore,
      workflowContextStore: _workflowContexts,
      recentWorkStore: _recentWork,
    );
    if (mounted) _refreshRecent();
  }

  void _refreshRecent() {
    setState(() => _recentTarget = _loadRecentTarget());
  }

  Future<_ContinueRecentTarget> _loadRecentTarget() async {
    final saved = (await _library.load()).items;
    final activeId = await _recentWork.activeGradingTestId();
    if (activeId != null) {
      SavedTest? item;
      for (final candidate in saved) {
        if (candidate.kind == 'mcq' && candidate.id == activeId) {
          item = candidate;
          break;
        }
      }
      if (item != null) {
        final papers = await _gradebook.listForTest(activeId);
        return _ContinueRecentTarget.grading(item, papers.length);
      }
      await _recentWork.clearActiveGrading();
    }

    final recent = await _recentWork.current();
    if (recent == null) return const _ContinueRecentTarget.fallback();
    if (recent.type == 'lesson' || recent.type == 'test') {
      SavedTest? item;
      for (final candidate in saved) {
        if (candidate.id == recent.id) {
          item = candidate;
          break;
        }
      }
      if (item == null) {
        await _recentWork.clearRecent();
        return const _ContinueRecentTarget.fallback();
      }
      return _ContinueRecentTarget.work(item);
    }
    if (recent.type == 'results') {
      final results = await _gradebook.listForTest(recent.id);
      if (results.isEmpty) {
        await _recentWork.clearRecent();
        return const _ContinueRecentTarget.fallback();
      }
      return _ContinueRecentTarget.results(results.first);
    }
    await _recentWork.clearRecent();
    return const _ContinueRecentTarget.fallback();
  }

  Future<void> _openGradePapers() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const GradePapersScreen()));
    if (mounted) _refreshRecent();
  }

  Future<void> _continueRecent(_ContinueRecentTarget target) async {
    if (target.type == 'grading' && target.saved != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GradingScreen(
            test: target.saved!.toMcqTest(),
            teachingContext: target.saved!.teachingContext,
            recentWorkStore: _recentWork,
          ),
        ),
      );
    } else if ((target.type == 'lesson' || target.type == 'test') &&
        target.saved != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SavedTestScreen(test: target.saved!)),
      );
    } else if (target.type == 'results' && target.result != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            testId: target.result!.testId,
            topic: target.result!.testTopic,
            recentWorkStore: _recentWork,
          ),
        ),
      );
    } else {
      final open = widget.onOpenMyWork ?? widget.onContinueRecent;
      if (open != null) {
        open();
      } else {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LibraryScreen()));
      }
    }
    if (mounted) _refreshRecent();
  }
}

class _ContinueRecentTarget {
  const _ContinueRecentTarget._({
    required this.type,
    required this.actionLabel,
    required this.subtitle,
    this.saved,
    this.result,
  });

  const _ContinueRecentTarget.fallback()
    : this._(
        type: 'fallback',
        actionLabel: 'Continue Recent',
        subtitle: 'Open My Work',
      );

  factory _ContinueRecentTarget.grading(SavedTest saved, int papers) =>
      _ContinueRecentTarget._(
        type: 'grading',
        actionLabel: 'Continue grading',
        subtitle: '${saved.topic} · $papers papers graded',
        saved: saved,
      );

  factory _ContinueRecentTarget.work(SavedTest saved) =>
      _ContinueRecentTarget._(
        type: saved.kind == 'lesson' ? 'lesson' : 'test',
        actionLabel: saved.kind == 'lesson'
            ? 'Continue lesson'
            : 'Continue test',
        subtitle: saved.topic,
        saved: saved,
      );

  factory _ContinueRecentTarget.results(GradedResult result) =>
      _ContinueRecentTarget._(
        type: 'results',
        actionLabel: 'Continue results',
        subtitle: result.testTopic,
        result: result,
      );

  final String type;
  final String actionLabel;
  final String subtitle;
  final SavedTest? saved;
  final GradedResult? result;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget iconBox() => Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.softBlue,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 22, color: AppColors.primary),
    );

    Widget labels() => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );

    return BayazCard(
      onTap: onTap,
      elevation: 3,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < 115) {
            return Row(
              children: [
                iconBox(),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: labels()),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [iconBox(), const Spacer(), labels()],
          );
        },
      ),
    );
  }
}
