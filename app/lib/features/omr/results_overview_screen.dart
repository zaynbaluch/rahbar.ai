import 'package:flutter/material.dart';

import '../../core/storage/local_store_load.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/empty_state.dart';
import '../../design_system/components/recovered_data_notice.dart';
import '../../design_system/theme/app_spacing.dart';
import 'grade_papers_screen.dart';
import 'gradebook_store.dart';
import 'graded_result.dart';
import 'results_screen.dart';

class ResultsOverviewScreen extends StatefulWidget {
  const ResultsOverviewScreen({super.key, this.store, this.onGradePapers});
  final GradebookStore? store;
  final VoidCallback? onGradePapers;
  @override
  State<ResultsOverviewScreen> createState() => _ResultsOverviewScreenState();
}

class _ResultsOverviewScreenState extends State<ResultsOverviewScreen> {
  late final GradebookStore _store = widget.store ?? GradebookStore();
  late Future<LocalStoreLoad<GradedResult>> _future = _store.loadAll();
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = _store.loadAll());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Class Results')),
    body: SafeArea(
      child: FutureBuilder<LocalStoreLoad<GradedResult>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: OutlinedButton(
                onPressed: _reload,
                child: const Text('Try again'),
              ),
            );
          }
          final load =
              snapshot.data ?? const LocalStoreLoad<GradedResult>(items: []);
          if (load.items.isEmpty) {
            return Column(
              children: [
                if (load.recoveredCorruptData)
                  RecoveredDataNotice(
                    count: load.recoveredFiles,
                    itemLabel: 'grading result',
                  ),
                Expanded(
                  child: BayazEmptyState(
                    asset: 'assets/ui/illustrations/empty_results.webp',
                    title: 'No results yet',
                    message:
                        'Grade your students’ answer sheets to see class results.',
                    action: FilledButton(
                      onPressed:
                          widget.onGradePapers ??
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const GradePapersScreen(),
                            ),
                          ),
                      child: const Text('Grade papers'),
                    ),
                  ),
                ),
              ],
            );
          }
          final groups = <String, List<GradedResult>>{};
          for (final result in load.items) {
            groups.putIfAbsent(result.testId, () => []).add(result);
          }
          final sessions = groups.values.toList()
            ..sort(
              (a, b) => b
                  .map((r) => r.createdAtMillis)
                  .reduce((x, y) => x > y ? x : y)
                  .compareTo(
                    a
                        .map((r) => r.createdAtMillis)
                        .reduce((x, y) => x > y ? x : y),
                  ),
            );
          final query = _search.text.trim().toLowerCase();
          final visible = sessions.where((group) {
            final first = group.first;
            final ctx = first.teachingContext;
            return query.isEmpty ||
                first.testTopic.toLowerCase().contains(query) ||
                (ctx?.className ?? '').toLowerCase().contains(query) ||
                (ctx?.subjectName ?? '').toLowerCase().contains(query);
          }).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              if (load.recoveredCorruptData) ...[
                RecoveredDataNotice(
                  count: load.recoveredFiles,
                  itemLabel: 'grading result',
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search results',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (visible.isNotEmpty)
                Text('Recent', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (final group in visible) ...[
                _SessionCard(results: group),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.results});
  final List<GradedResult> results;
  @override
  Widget build(BuildContext context) {
    final first = results.first;
    final average =
        results.map((r) => r.pct).reduce((a, b) => a + b) / results.length;
    final ctx = first.teachingContext;
    final label = [
      ctx?.className,
      ctx?.subjectName,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    final newest = results
        .map((r) => r.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return BayazCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ResultsScreen(testId: first.testId, topic: first.testTopic),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(first.testTopic, style: Theme.of(context).textTheme.titleMedium),
          if (label.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(label),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text('${results.length} students'),
              const Spacer(),
              Text('${average.round()}% average'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                '${newest.day}/${newest.month}/${newest.year}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ],
      ),
    );
  }
}
