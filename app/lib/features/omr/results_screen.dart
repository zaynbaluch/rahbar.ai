import 'package:flutter/material.dart';

import '../../design_system/components/empty_state.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/components/recovered_data_notice.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../../core/storage/local_store_load.dart';
import 'gradebook_store.dart';
import 'graded_result.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.testId, required this.topic});

  final String testId;
  final String topic;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final _store = GradebookStore();
  late Future<LocalStoreLoad<GradedResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = _store.loadForTest(widget.testId);
  }

  void _reload() {
    setState(() {
      _future = _store.loadForTest(widget.testId);
    });
  }

  Future<void> _refresh() async {
    final next = _store.loadForTest(widget.testId);
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _delete(GradedResult result) async {
    await _store.delete(result.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Class results')),
      body: SafeArea(
        child: FutureBuilder<LocalStoreLoad<GradedResult>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return BayazEmptyState(
                asset: 'assets/ui/illustrations/no_search_results.webp',
                title: 'Could not load these results',
                message:
                    'The saved gradebook could not be read from this device.',
                action: FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              );
            }
            final load = snapshot.data ??
                const LocalStoreLoad<GradedResult>(items: []);
            final results = load.items;
            if (results.isEmpty) {
              return Column(
                children: [
                  if (load.recoveredCorruptData)
                    RecoveredDataNotice(
                      count: load.recoveredFiles,
                      itemLabel: 'grading result',
                    ),
                  const Expanded(
                    child: BayazEmptyState(
                      asset: 'assets/ui/illustrations/empty_results.webp',
                      title: 'No sheets saved for this paper',
                      message:
                          'Grade an answer sheet from this test and save it to build the class summary.',
                    ),
                  ),
                ],
              );
            }

            final total = results.first.total;
            final average = results.map((r) => r.pct).reduce((a, b) => a + b) /
                results.length;
            final high = results
                .map((r) => r.correct)
                .reduce((a, b) => a > b ? a : b);
            final low = results
                .map((r) => r.correct)
                .reduce((a, b) => a < b ? a : b);

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
                  if (load.recoveredCorruptData) ...[
                    RecoveredDataNotice(
                      count: load.recoveredFiles,
                      itemLabel: 'grading result',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  _ResultsHeader(
                    topic: widget.topic,
                    testId: widget.testId,
                    students: results.length,
                    average: average.round(),
                    high: high,
                    low: low,
                    total: total,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Students',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  for (final result in results) ...[
                    Dismissible(
                      key: ValueKey(result.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmDelete(result),
                      onDismissed: (_) => _delete(result),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.delete_outline,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
                      ),
                      child: _StudentResultCard(result: result),
                    ),
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

  Future<bool> _confirmDelete(GradedResult result) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this result?'),
            content: Text(
              '${result.studentName}’s saved score will be removed from this device.',
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

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.topic,
    required this.testId,
    required this.students,
    required this.average,
    required this.high,
    required this.low,
    required this.total,
  });

  final String topic;
  final String testId;
  final int students;
  final int average;
  final int high;
  final int low;
  final int total;

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
          Text(
            topic,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Paper ID $testId',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - AppSpacing.sm) / 2;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _StatTile(width: width, value: '$students', label: 'Students'),
                  _StatTile(width: width, value: '$average%', label: 'Average'),
                  _StatTile(width: width, value: '$high/$total', label: 'Highest'),
                  _StatTile(width: width, value: '$low/$total', label: 'Lowest'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.width, required this.value, required this.label});
  final double width;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
          ),
        ],
      ),
    );
  }
}

class _StudentResultCard extends StatelessWidget {
  const _StudentResultCard({required this.result});
  final GradedResult result;

  @override
  Widget build(BuildContext context) {
    final date = result.createdAt;
    final passed = result.pct >= 50;
    return BayazCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: passed
                  ? const Color(0xFFDDF5E8)
                  : Theme.of(context).colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${result.pct}%',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: passed
                        ? AppColors.success
                        : Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.studentName,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusChip(
                      label: '${result.correct}/${result.total}',
                      icon: Icons.check_circle_outline,
                      backgroundColor: passed
                          ? const Color(0xFFDDF5E8)
                          : Theme.of(context).colorScheme.errorContainer,
                      foregroundColor: passed
                          ? AppColors.success
                          : Theme.of(context).colorScheme.error,
                    ),
                    StatusChip(
                      label:
                          '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                      icon: Icons.calendar_today_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
