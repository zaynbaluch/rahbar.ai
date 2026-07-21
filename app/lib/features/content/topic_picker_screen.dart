import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/components/brand_app_bar.dart';
import '../../design_system/components/empty_state.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/section_header.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_radii.dart';
import '../../design_system/theme/app_spacing.dart';
import '../generation/generation_screen.dart';
import '../resources/offline_ai_navigation.dart';
import '../curriculum/recent_access_store.dart';
import '../library/library_screen.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import 'content_service.dart';
import 'topic_screen.dart';

/// Teacher home and curriculum browser. Every number and action on this screen
/// comes from the shipped content pack or the local library.
class TopicPickerScreen extends StatefulWidget {
  const TopicPickerScreen({
    super.key,
    this.classCode = '6',
    this.subjectCode = 'general_science',
    this.className = 'Class 6',
    this.subjectName = 'General Science',
  });

  final String classCode;
  final String subjectCode;
  final String className;
  final String subjectName;

  @override
  State<TopicPickerScreen> createState() => _TopicPickerScreenState();
}

class _TopicPickerScreenState extends State<TopicPickerScreen> {
  final _content = ContentService();
  final _library = LibraryStore();
  final _search = TextEditingController();

  List<Topic> _all = [];
  Future<List<SavedTest>>? _recentFuture;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _content.init();
      if (!mounted) return;
      setState(() {
        _all = _content.listTopics();
        _recentFuture = _library.list();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Topic> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              t.summary.toLowerCase().contains(q) ||
              t.sectionNo.toLowerCase().startsWith(q),
        )
        .toList();
  }

  Map<int, List<Topic>> _groupByChapter(List<Topic> topics) {
    final grouped = <int, List<Topic>>{};
    for (final topic in topics) {
      grouped.putIfAbsent(topic.chapter, () => []).add(topic);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: BrandAppBarTitle(subtitle: 'Offline teacher toolkit'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _errorView()
            : _buildHome(),
      ),
    );
  }

  Widget _buildHome() {
    final topics = _visible;
    final query = _search.text.trim();
    final grouped = _groupByChapter(topics);
    final chapterCount = _all.map((t) => t.chapter).toSet().length;
    final itemCount = _all.fold<int>(0, (sum, t) => sum + t.nItems);

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        _HeroPanel(
          topicCount: _all.length,
          chapterCount: chapterCount,
          itemCount: itemCount,
        ),
        const SizedBox(height: AppSpacing.lg),
        FutureBuilder<List<SavedTest>>(
          future: _recentFuture,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const [];
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: 'Continue your work',
                  subtitle: 'Recently saved on this device',
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.take(4).length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) =>
                        _RecentCard(test: items[index]),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            );
          },
        ),
        SectionHeader(
          title: 'Choose a curriculum topic',
          subtitle:
              '${widget.className} ${widget.subjectName} · verified offline content',
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search cells, mixtures, digestion…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (topics.isEmpty)
          _noMatch(query)
        else if (query.isNotEmpty)
          for (final topic in topics) ...[
            _TopicCard(topic: topic, onTap: () => _openTopic(topic)),
            const SizedBox(height: AppSpacing.sm),
          ]
        else
          for (final entry in grouped.entries) ...[
            _ChapterCard(
              chapter: entry.key,
              topics: entry.value,
              onTopic: _openTopic,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        if (query.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _CustomTopicCard(onTap: () => _openCustomTopic('')),
        ],
      ],
    );
  }

  void _openTopic(Topic topic) {
    unawaited(
      RecentAccessStore().record(
        classCode: widget.classCode,
        subjectCode: widget.subjectCode,
        topicId: topic.id,
        topicTitle: topic.title,
      ),
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TopicScreen(content: _content, topic: topic),
          ),
        )
        .then((_) {
          if (mounted) setState(() => _recentFuture = _library.list());
        });
  }

  void _openCustomTopic(String topic) {
    openOfflineAiScreen(
      context,
      (_) => GenerationScreen(initialTopic: topic),
    );
  }

  Widget _noMatch(String query) => BayazEmptyState(
    asset: 'assets/ui/illustrations/no_search_results.webp',
    title: 'No curriculum topic found',
    message:
        '“$query” is not in the shipped Class 6 content pack. The existing offline AI fallback can still attempt it, but it takes longer and should be reviewed.',
    action: OutlinedButton.icon(
      icon: const Icon(Icons.auto_awesome_outlined),
      label: const Text('Use custom generation'),
      onPressed: () => _openCustomTopic(query),
    ),
  );

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 44,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Could not open the content pack',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _error ?? '',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.topicCount,
    required this.chapterCount,
    required this.itemCount,
  });

  final int topicCount;
  final int chapterCount;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -20,
            child: Opacity(
              opacity: 0.16,
              child: Image.asset(
                'assets/ui/branding/bayaz_logo.png',
                width: 132,
                height: 132,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prepare your next class',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Create a lesson plan or verified MCQ paper directly from the curriculum pack.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _HeroStat(label: '$chapterCount chapters'),
                  _HeroStat(label: '$topicCount topics'),
                  _HeroStat(label: '$itemCount verified MCQs'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.test});
  final SavedTest test;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 245,
      child: BayazCard(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => SavedTestScreen(test: test))),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: test.kind == 'mcq'
                    ? AppColors.softGold
                    : AppColors.softBlue,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                test.kind == 'mcq'
                    ? Icons.fact_check_outlined
                    : Icons.menu_book_outlined,
                color: test.kind == 'mcq'
                    ? AppColors.warningText
                    : AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    test.topic,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    test.kind == 'mcq' ? 'MCQ test' : 'Lesson plan',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.chapter,
    required this.topics,
    required this.onTopic,
  });

  final int chapter;
  final List<Topic> topics;
  final ValueChanged<Topic> onTopic;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: chapter == 1,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          0,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.softBlue,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            '$chapter',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: AppColors.primary),
          ),
        ),
        title: Text('Chapter $chapter'),
        subtitle: Text('${topics.length} curriculum topics'),
        children: [
          for (final topic in topics)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: _TopicCard(topic: topic, onTap: () => onTopic(topic)),
            ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.onTap});

  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      onTap: onTap,
      color: const Color(0xFFFBFCFF),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 46),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.softBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              topic.sectionNo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (topic.summary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    topic.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                StatusChip(
                  label: topic.hasTest
                      ? '${topic.nItems} verified questions'
                      : '${topic.nItems} questions available',
                  icon: topic.hasTest
                      ? Icons.verified_outlined
                      : Icons.info_outline,
                  backgroundColor: topic.hasTest
                      ? AppColors.softBlue
                      : AppColors.softGold,
                  foregroundColor: topic.hasTest
                      ? AppColors.navy
                      : AppColors.warningText,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomTopicCard extends StatelessWidget {
  const _CustomTopicCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      onTap: onTap,
      color: AppColors.softBlue,
      borderColor: const Color(0xFFC9D6FF),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            color: AppColors.primary,
            size: 28,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Topic outside the curriculum pack?',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  'Use the existing offline AI fallback. It is slower and its output should be reviewed.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
        ],
      ),
    );
  }
}
