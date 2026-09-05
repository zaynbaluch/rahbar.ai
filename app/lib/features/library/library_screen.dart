import 'package:flutter/material.dart';

import '../../core/storage/local_store_load.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/empty_state.dart';
import '../../design_system/components/recovered_data_notice.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../curriculum/recent_work_store.dart';
import '../generation/lesson_plan_view.dart';
import '../generation/mcq_test_view.dart';
import '../omr/gradebook_store.dart';
import 'library_store.dart';
import 'saved_test.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.store,
    this.gradebookStore,
    this.onPrepareLesson,
    this.onCreateTest,
    this.recentWorkStore,
  });

  final LibraryStore? store;
  final GradebookStore? gradebookStore;
  final VoidCallback? onPrepareLesson;
  final VoidCallback? onCreateTest;
  final RecentWorkStore? recentWorkStore;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryStore _store = widget.store ?? LibraryStore();
  late final GradebookStore _gradebook =
      widget.gradebookStore ?? GradebookStore();
  late final RecentWorkStore _recentWork =
      widget.recentWorkStore ?? RecentWorkStore();
  final _search = TextEditingController();
  late Future<LocalStoreLoad<SavedTest>> _future = _store.load();
  String _filter = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = _store.load());

  Future<void> _refresh() async {
    final next = _store.load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _delete(SavedTest item) async {
    await _store.delete(item.id);
    await _recentWork.invalidateTarget(item.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My Work')),
    body: SafeArea(
      child: FutureBuilder<LocalStoreLoad<SavedTest>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _LibraryError(onRetry: _reload);
          }
          final load =
              snapshot.data ?? const LocalStoreLoad<SavedTest>(items: []);
          final all = load.items;
          final query = _search.text.trim().toLowerCase();
          final visible = all
              .where((item) {
                final matchesKind = _filter == 'all' || item.kind == _filter;
                final ctx = item.teachingContext;
                final matchesQuery =
                    query.isEmpty ||
                    item.topic.toLowerCase().contains(query) ||
                    (ctx?.className ?? '').toLowerCase().contains(query) ||
                    (ctx?.subjectName ?? '').toLowerCase().contains(query);
                return matchesKind && matchesQuery;
              })
              .toList(growable: false);

          if (all.isEmpty) {
            return Column(
              children: [
                if (load.recoveredCorruptData)
                  RecoveredDataNotice(
                    count: load.recoveredFiles,
                    itemLabel: 'saved item',
                  ),
                Expanded(
                  child: BayazEmptyState(
                    asset: 'assets/ui/illustrations/empty_library.webp',
                    title: 'Nothing saved yet',
                    message: '',
                    action: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: widget.onPrepareLesson,
                          child: const Text('Create Lesson'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton(
                          onPressed: widget.onCreateTest,
                          child: const Text('Create Test'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              if (load.recoveredCorruptData)
                RecoveredDataNotice(
                  count: load.recoveredFiles,
                  itemLabel: 'saved item',
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search your work',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _search.text.isEmpty
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
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('All')),
                          ButtonSegment(
                            value: 'lesson',
                            label: Text('Lessons'),
                          ),
                          ButtonSegment(value: 'mcq', label: Text('Tests')),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (value) =>
                            setState(() => _filter = value.first),
                        showSelectedIcon: false,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? _NoMatches(
                        onClear: () {
                          _search.clear();
                          setState(() => _filter = 'all');
                        },
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.xs,
                            AppSpacing.md,
                            AppSpacing.xl,
                          ),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final item = visible[index];
                            return Dismissible(
                              key: ValueKey(item.id),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) => _confirmDelete(item),
                              onDismissed: (_) => _delete(item),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.lg,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                              ),
                              child: _WorkCard(item: item),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Future<bool> _confirmDelete(SavedTest item) async {
    final hasResults =
        item.kind == 'mcq' &&
        (await _gradebook.listForTest(item.id)).isNotEmpty;
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this item?'),
            content: Text(
              hasResults
                  ? '“${item.topic}” will be removed from My Work. Existing class results will remain, but you will no longer be able to grade more papers from this test.'
                  : '“${item.topic}” will be removed from My Work. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({required this.item});
  final SavedTest item;

  @override
  Widget build(BuildContext context) {
    final isTest = item.kind == 'mcq';
    final ctx = item.teachingContext;
    final contextLabel = [
      ctx?.className,
      ctx?.subjectName,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final type = isTest
        ? 'Test · ${item.toMcqTest().count} questions'
        : 'Lesson Plan';
    final date = item.createdAt;
    return BayazCard(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => SavedTestScreen(test: item))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isTest ? AppColors.softGold : AppColors.softBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isTest ? Icons.fact_check_outlined : Icons.menu_book_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.topic,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(type),
                if (contextLabel.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(contextLabel),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${date.day}/${date.month}/${date.year}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class SavedTestScreen extends StatelessWidget {
  const SavedTestScreen({super.key, required this.test});
  final SavedTest test;

  @override
  Widget build(BuildContext context) {
    if (test.kind == 'mcq') {
      return McqTestScreen(
        test: test.toMcqTest(),
        saved: true,
        teachingContext: test.teachingContext,
      );
    }
    final structured = test.toLessonPlan();
    if (structured != null) {
      return LessonPlanReadOnlyScreen(
        plan: structured,
        teachingContext: test.teachingContext,
      );
    }
    return _LegacyLessonScreen(test: test);
  }
}

class _LegacyLessonScreen extends StatelessWidget {
  const _LegacyLessonScreen({required this.test});
  final SavedTest test;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(test.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: BayazCard(
          child: SelectableText(
            test.rawOutput,
            style: const TextStyle(height: 1.5),
          ),
        ),
      ),
    ),
  );
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onClear});
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Nothing matches', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        const Text('Try another search or change the filter.'),
        TextButton(onPressed: onClear, child: const Text('Clear filters')),
      ],
    ),
  );
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Could not open My Work'),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
