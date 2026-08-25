import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../curriculum/curriculum_catalog.dart';
import '../curriculum/recent_access_store.dart';
import '../curriculum/teaching_context.dart';
import '../curriculum/teaching_context_selector.dart';
import '../curriculum/workflow_context_store.dart';
import '../generation/generation_screen.dart';
import '../generation/lesson_plan_view.dart';
import '../onboarding/onboarding_store.dart';
import '../resources/offline_ai_navigation.dart';
import 'content_service.dart';

/// The two intent-specific topic-picking flows exposed from Home.
enum TopicPickerMode { lesson, test }

class TopicPickerScreen extends StatefulWidget {
  const TopicPickerScreen({
    super.key,
    required this.mode,
    required this.teachingContext,
    this.showContextChange = false,
    this.content,
    this.onboardingStore,
    this.workflowContextStore,
  });

  final TopicPickerMode mode;
  final TeachingContext teachingContext;
  final bool showContextChange;
  final ContentService? content;
  final OnboardingStore? onboardingStore;
  final WorkflowContextStore? workflowContextStore;

  @override
  State<TopicPickerScreen> createState() => _TopicPickerScreenState();
}

class _TopicPickerScreenState extends State<TopicPickerScreen> {
  late final ContentService _content;
  late final bool _ownsContent;
  late final OnboardingStore _onboardingStore;
  late final WorkflowContextStore _workflowContexts;
  late TeachingContext _context;
  final _search = TextEditingController();

  List<Topic> _all = const [];
  String? _error;
  bool _loading = true;

  String get _workflowKey =>
      widget.mode == TopicPickerMode.lesson ? 'lesson' : 'test';
  String get _title =>
      widget.mode == TopicPickerMode.lesson ? 'Prepare Lesson' : 'Create Test';
  String get _customLabel => widget.mode == TopicPickerMode.lesson
      ? 'Create a custom lesson'
      : 'Create a custom test';

  @override
  void initState() {
    super.initState();
    _ownsContent = widget.content == null;
    _content = widget.content ?? ContentService();
    _onboardingStore = widget.onboardingStore ?? OnboardingStore();
    _workflowContexts = widget.workflowContextStore ?? WorkflowContextStore();
    _context = widget.teachingContext;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    if (_ownsContent) _content.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _content.init();
      if (!mounted) return;
      setState(() {
        _all = _content.listTopics();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  List<Topic> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _all;
    return _all
        .where((topic) {
          return topic.title.toLowerCase().contains(query) ||
              topic.summary.toLowerCase().contains(query) ||
              topic.sectionNo.toLowerCase().startsWith(query);
        })
        .toList(growable: false);
  }

  Map<int, List<Topic>> _groupByChapter(List<Topic> topics) {
    final grouped = <int, List<Topic>>{};
    for (final topic in topics) {
      grouped.putIfAbsent(topic.chapter, () => <Topic>[]).add(topic);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _errorView()
            : _contentView(),
      ),
    );
  }

  Widget _contentView() {
    final query = _search.text.trim();
    final topics = _visible;
    final grouped = _groupByChapter(topics);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        if (widget.showContextChange) ...[
          _ContextRow(context: _context, onChange: _changeContext),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search topics',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (topics.isEmpty)
          _CustomTopicPrompt(
            label: _customLabel,
            query: query,
            onTap: () => _openCustom(query),
          )
        else if (query.isNotEmpty)
          for (final topic in topics) ...[
            _TopicTile(topic: topic, onTap: () => _openTopic(topic)),
            const SizedBox(height: AppSpacing.sm),
          ]
        else
          for (final entry in grouped.entries) ...[
            Text(
              'Chapter ${entry.key}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final topic in entry.value) ...[
              _TopicTile(topic: topic, onTap: () => _openTopic(topic)),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.sm),
          ],
        if (topics.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Column(
              children: [
                Text(
                  "Can't find the topic?",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                TextButton(
                  onPressed: () => _openCustom(query),
                  child: Text(_customLabel),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openTopic(Topic topic) async {
    unawaited(
      RecentAccessStore().record(
        classCode: _context.classCode ?? '',
        subjectCode: _context.subjectCode ?? '',
        topicId: topic.id,
        topicTitle: topic.title,
      ),
    );
    if (widget.mode == TopicPickerMode.lesson) {
      final plan = _content.assemblePlan(topic.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LessonPlanScreen(
            content: _content,
            topic: topic,
            plan: plan,
            teachingContext: _context,
          ),
        ),
      );
      return;
    }
    // Phase 4 replaces this branch with the count-only test setup.
  }

  void _openCustom(String query) {
    openOfflineAiScreen(
      context,
      (_) => GenerationScreen(
        initialTopic: query,
        initialKind: widget.mode == TopicPickerMode.lesson ? 'lesson' : 'mcq',
        dedicated: true,
        teachingContext: _context,
      ),
    );
  }

  Future<void> _changeContext() async {
    final state = await _onboardingStore.read();
    if (!mounted) return;
    final selectedClasses = CurriculumCatalog.classes
        .where((item) => state.selectedClasses.contains(item.code))
        .toList(growable: false);
    final next = await showTeachingContextSelector(
      context,
      classes: selectedClasses,
      selectedSubjectsByClass: state.selectedSubjectsByClass,
      initial: _context,
    );
    if (next == null || !mounted) return;
    await _workflowContexts.save(_workflowKey, next);
    if (!mounted) return;
    setState(() => _context = next);
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 44),
          const SizedBox(height: AppSpacing.sm),
          const Text('Could not open topics'),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({required this.context, required this.onChange});
  final TeachingContext context;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final label = [
      this.context.className,
      this.context.subjectName,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        TextButton(onPressed: onChange, child: const Text('Change')),
      ],
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic, required this.onTap});
  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.softBlue,
              shape: BoxShape.circle,
            ),
            child: Text(
              topic.sectionNo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              topic.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _CustomTopicPrompt extends StatelessWidget {
  const _CustomTopicPrompt({
    required this.label,
    required this.query,
    required this.onTap,
  });
  final String label;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            query.isEmpty
                ? 'Choose another topic'
                : 'No topic found for "$query"',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonal(onPressed: onTap, child: Text(label)),
        ],
      ),
    );
  }
}
