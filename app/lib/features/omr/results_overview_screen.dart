import 'package:flutter/material.dart';

import '../../design_system/components/brand_app_bar.dart';
import '../../design_system/components/empty_state.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/section_header.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import 'gradebook_store.dart';
import 'graded_result.dart';
import 'results_screen.dart';

class ResultsOverviewScreen extends StatefulWidget {
  const ResultsOverviewScreen({super.key});

  @override
  State<ResultsOverviewScreen> createState() => _ResultsOverviewScreenState();
}

class _ResultsOverviewScreenState extends State<ResultsOverviewScreen> {
  final _store = GradebookStore();
  late Future<List<GradedResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = _store.listAll();
  }

  void _reload() => setState(() => _future = _store.listAll());

  Future<void> _refresh() async {
    final next = _store.listAll();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: BrandAppBarTitle(subtitle: 'Saved grading sessions'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<GradedResult>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(error: '${snapshot.error}', onRetry: _reload);
            }
            final all = snapshot.data ?? const [];
            if (all.isEmpty) {
              return const BayazEmptyState(
                asset: 'assets/ui/illustrations/empty_results.webp',
                title: 'No grading results yet',
                message:
                    'Open a saved or newly created test, grade an answer sheet, and save the result.',
              );
            }

            final groups = <String, List<GradedResult>>{};
            for (final result in all) {
              groups.putIfAbsent(result.testId, () => []).add(result);
            }
            final sessions = groups.values.toList()
              ..sort(
                (a, b) =>
                    b.first.createdAtMillis.compareTo(a.first.createdAtMillis),
              );

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                children: [
                  const SectionHeader(
                    title: 'Class results',
                    subtitle:
                        'Every card below is backed by answer sheets already saved on this device.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final group in sessions) ...[
                    _SessionCard(results: group),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.results});

  final List<GradedResult> results;

  @override
  Widget build(BuildContext context) {
    final first = results.first;
    final total = first.total;
    final average =
        results.map((r) => r.pct).reduce((a, b) => a + b) / results.length;
    final highest = results
        .map((r) => r.correct)
        .reduce((a, b) => a > b ? a : b);
    final d = first.createdAt;

    return BayazCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ResultsScreen(testId: first.testId, topic: first.testTopic),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.softBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  first.testTopic,
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
                      label: '${results.length} students',
                      icon: Icons.people_outline,
                    ),
                    StatusChip(
                      label: '${average.round()}% average',
                      icon: Icons.insights_outlined,
                      backgroundColor: AppColors.softGold,
                      foregroundColor: AppColors.warningText,
                    ),
                    StatusChip(
                      label: '$highest/$total high',
                      icon: Icons.trending_up,
                      backgroundColor: const Color(0xFFDDF5E8),
                      foregroundColor: AppColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · ID ${first.testId}',
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
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

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
            Icon(
              Icons.error_outline,
              size: 44,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Could not open results',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
