import 'package:flutter/material.dart';

import '../../design_system/components/brand_app_bar.dart';
import '../../design_system/components/empty_state.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../generation/lesson_plan_view.dart';
import '../generation/mcq_test_view.dart';
import 'library_store.dart';
import 'saved_test.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _store = LibraryStore();
  final _search = TextEditingController();
  late Future<List<SavedTest>> _future;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _store.list();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = _store.list());

  Future<void> _refresh() async {
    final next = _store.list();
    setState(() => _future = next);
    await next;
  }

  Future<void> _delete(SavedTest test) async {
    await _store.delete(test.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const BrandAppBarTitle(subtitle: 'Saved teaching materials'),
        actions: [
          IconButton(
            tooltip: 'Refresh Library',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<SavedTest>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _LibraryError(error: '${snapshot.error}', onRetry: _reload);
            }
            final all = snapshot.data ?? const [];
            final query = _search.text.trim().toLowerCase();
            final visible = all.where((item) {
              final matchesKind = _filter == 'all' || item.kind == _filter;
              final matchesQuery =
                  query.isEmpty || item.topic.toLowerCase().contains(query);
              return matchesKind && matchesQuery;
            }).toList();

            return Column(
              children: [
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
                          hintText: 'Search saved topics',
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
                              icon: Icon(Icons.menu_book_outlined),
                            ),
                            ButtonSegment(
                              value: 'mcq',
                              label: Text('Tests'),
                              icon: Icon(Icons.fact_check_outlined),
                            ),
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
                      ? _emptyState(all.isEmpty)
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
                                      right: AppSpacing.lg),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .errorContainer,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(Icons.delete_outline,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer),
                                ),
                                child: _LibraryCard(item: item),
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
  }

  Widget _emptyState(bool libraryEmpty) {
    if (libraryEmpty) {
      return const BayazEmptyState(
        asset: 'assets/ui/illustrations/empty_library.webp',
        title: 'Your Library is empty',
        message:
            'Save a lesson plan or MCQ paper and it will remain available here for reopening and printing.',
      );
    }
    final asset = _filter == 'lesson'
        ? 'assets/ui/illustrations/no_saved_lessons.png'
        : _filter == 'mcq'
            ? 'assets/ui/illustrations/no_saved_tests.png'
            : 'assets/ui/illustrations/no_search_results.webp';
    return BayazEmptyState(
      asset: asset,
      title: 'Nothing matches this view',
      message: 'Change the filter or clear the search to see other saved items.',
      action: TextButton.icon(
        onPressed: () {
          _search.clear();
          setState(() => _filter = 'all');
        },
        icon: const Icon(Icons.filter_alt_off_outlined),
        label: const Text('Clear filters'),
      ),
    );
  }

  Future<bool> _confirmDelete(SavedTest item) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete saved item?'),
            content: Text(
              '“${item.topic}” will be removed from this device. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.item});
  final SavedTest item;

  @override
  Widget build(BuildContext context) {
    final date = item.createdAt;
    final isTest = item.kind == 'mcq';
    return BayazCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SavedTestScreen(test: item),
      )),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isTest ? AppColors.softGold : AppColors.softBlue,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              isTest ? Icons.fact_check_outlined : Icons.menu_book_outlined,
              color: isTest ? AppColors.warningText : AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusChip(
                      label: isTest ? 'MCQ test' : 'Lesson plan',
                      icon: isTest
                          ? Icons.checklist_rounded
                          : Icons.menu_book_rounded,
                      backgroundColor:
                          isTest ? AppColors.softGold : AppColors.softBlue,
                      foregroundColor: isTest
                          ? AppColors.warningText
                          : AppColors.navy,
                    ),
                    if (item.fromPack)
                      const StatusChip(
                        label: 'Curriculum pack',
                        icon: Icons.verified_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textSecondary),
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
      return McqTestScreen(test: test.toMcqTest(), saved: true);
    }
    final structured = test.toLessonPlan();
    if (structured != null) {
      return LessonPlanReadOnlyScreen(plan: structured);
    }
    return _LegacyLessonScreen(test: test);
  }
}

class _LegacyLessonScreen extends StatelessWidget {
  const _LegacyLessonScreen({required this.test});
  final SavedTest test;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(test.topic,
            maxLines: 1, overflow: TextOverflow.ellipsis),
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
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 44, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: AppSpacing.sm),
            Text('Could not open the Library',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
