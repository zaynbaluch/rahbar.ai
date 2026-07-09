import 'package:flutter/material.dart';

import 'gradebook_store.dart';
import 'graded_result.dart';

/// Class results for one test: every graded sheet, with class stats (count,
/// average, high/low). Backed by [GradebookStore].
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.testId, required this.topic});

  final String testId;
  final String topic;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final _store = GradebookStore();
  late Future<List<GradedResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = _store.listForTest(widget.testId);
  }

  void _reload() =>
      setState(() => _future = _store.listForTest(widget.testId));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Class Results')),
      body: FutureBuilder<List<GradedResult>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final results = snap.data ?? [];
          if (results.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No graded sheets yet.\nGrade a sheet and tap Save.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final total = results.first.total;
          final avg = results.map((r) => r.pct).reduce((a, b) => a + b) /
              results.length;
          final high = results.map((r) => r.correct).reduce((a, b) => a > b ? a : b);
          final low = results.map((r) => r.correct).reduce((a, b) => a < b ? a : b);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.topic, style: theme.textTheme.titleMedium),
              Text('Test ID ${widget.testId}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat(label: 'Students', value: '${results.length}'),
                      _Stat(label: 'Average', value: '${avg.round()}%'),
                      _Stat(label: 'High', value: '$high/$total'),
                      _Stat(label: 'Low', value: '$low/$total'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final r in results)
                Dismissible(
                  key: ValueKey(r.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: theme.colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline),
                  ),
                  onDismissed: (_) async {
                    await _store.delete(r.id);
                    _reload();
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: r.pct >= 50
                          ? Colors.green.shade100
                          : theme.colorScheme.errorContainer,
                      child: Text('${r.pct}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(r.studentName),
                    trailing: Text('${r.correct}/${r.total}',
                        style: theme.textTheme.titleMedium),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = theme.colorScheme.onPrimaryContainer;
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleLarge
                ?.copyWith(color: onColor, fontWeight: FontWeight.bold)),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: onColor)),
      ],
    );
  }
}
