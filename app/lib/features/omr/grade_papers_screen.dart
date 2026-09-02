import 'package:flutter/material.dart';

import '../../core/storage/local_store_load.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/empty_state.dart';
import '../../design_system/theme/app_spacing.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import 'grading_screen.dart';

class GradePapersScreen extends StatefulWidget {
  const GradePapersScreen({super.key, this.store});
  final LibraryStore? store;

  @override
  State<GradePapersScreen> createState() => _GradePapersScreenState();
}

class _GradePapersScreenState extends State<GradePapersScreen> {
  late final LibraryStore _store = widget.store ?? LibraryStore();
  final _search = TextEditingController();
  late Future<LocalStoreLoad<SavedTest>> _future = _store.load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Grade Papers')),
    body: SafeArea(
      child: FutureBuilder<LocalStoreLoad<SavedTest>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _LoadError(
              onRetry: () => setState(() => _future = _store.load()),
            );
          }
          final all = (snapshot.data?.items ?? const <SavedTest>[])
              .where((item) => item.kind == 'mcq')
              .toList(growable: false);
          final query = _search.text.trim().toLowerCase();
          final visible = all
              .where((item) {
                final ctx = item.teachingContext;
                return query.isEmpty ||
                    item.topic.toLowerCase().contains(query) ||
                    (ctx?.className ?? '').toLowerCase().contains(query) ||
                    (ctx?.subjectName ?? '').toLowerCase().contains(query);
              })
              .toList(growable: false);
          if (all.isEmpty) {
            return const BayazEmptyState(
              asset: 'assets/ui/illustrations/no_saved_tests.webp',
              title: 'No saved tests yet',
              message:
                  'Create or share a test first, then come back here to grade papers.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              Text(
                'Which test are you grading?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search tests',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: Text('No matching tests.')),
                )
              else ...[
                Text('Recent', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                for (final item in visible) ...[
                  _TestCard(item: item),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ],
          );
        },
      ),
    ),
  );
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.item});
  final SavedTest item;

  @override
  Widget build(BuildContext context) {
    final test = item.toMcqTest();
    final ctx = item.teachingContext;
    final contextLabel = [
      ctx?.className,
      ctx?.subjectName,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    final d = item.createdAt;
    return BayazCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              GradingScreen(test: test, teachingContext: item.teachingContext),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.topic, style: Theme.of(context).textTheme.titleMedium),
          if (contextLabel.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(contextLabel),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${test.count} questions · ${d.day}/${d.month}/${d.year}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Could not open saved tests.'),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
