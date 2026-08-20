import 'package:flutter/material.dart';

import '../generation/mcq_test_view.dart';
import 'library_store.dart';
import 'saved_test.dart';

/// Lists saved tests so a teacher can reopen (and re-print) a generated test
/// without paying the multi-minute generation cost again.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _store = LibraryStore();
  late Future<List<SavedTest>> _future;

  @override
  void initState() {
    super.initState();
    _future = _store.list();
  }

  void _reload() => setState(() => _future = _store.list());

  Future<void> _delete(SavedTest t) async {
    await _store.delete(t.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Tests')),
      body: FutureBuilder<List<SavedTest>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final tests = snap.data ?? [];
          if (tests.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No saved tests yet.\nGenerate a test and tap Save.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            itemCount: tests.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = tests[i];
              final d = t.createdAt;
              return Dismissible(
                key: ValueKey(t.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline),
                ),
                onDismissed: (_) => _delete(t),
                child: ListTile(
                  leading: Icon(
                      t.kind == 'mcq' ? Icons.checklist : Icons.menu_book),
                  title: Text(t.topic, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${t.kind == 'mcq' ? 'MCQ Test' : 'Lesson Plan'} · '
                      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
                      '${d.day.toString().padLeft(2, '0')}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SavedTestScreen(test: t),
                  )),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Read-only view of a saved test: structured MCQ cards (with key + PDF export)
/// or the raw lesson-plan text. No model load — reuses the stored output.
class SavedTestScreen extends StatelessWidget {
  const SavedTestScreen({super.key, required this.test});

  final SavedTest test;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(test.topic, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: test.kind == 'mcq'
              ? McqTestView(test: test.toMcqTest(), saved: true)
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(test.rawOutput,
                      style: const TextStyle(height: 1.4)),
                ),
        ),
      ),
    );
  }
}
