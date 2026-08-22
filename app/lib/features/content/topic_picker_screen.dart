import 'package:flutter/material.dart';

import '../generation/generation_screen.dart';
import '../library/library_screen.dart';
import 'content_service.dart';
import 'topic_screen.dart';

/// Home: pick a topic from the curriculum.
///
/// Replaces the old free-text box (`generation_screen.dart`), which let a teacher type
/// anything and then wait ~3.5 min to find out whether the model could do it. The pack
/// (ADR-008) knows exactly which topics it covers, so we show them: bounded, browsable,
/// and instant.
///
/// Anything the picker cannot match still has a way through — [GenerationScreen], the
/// on-device SLM escape hatch — so "it can generate for any topic, offline" stays true.
class TopicPickerScreen extends StatefulWidget {
  const TopicPickerScreen({super.key});

  @override
  State<TopicPickerScreen> createState() => _TopicPickerScreenState();
}

class _TopicPickerScreenState extends State<TopicPickerScreen> {
  final _content = ContentService();
  final _search = TextEditingController();

  List<Topic> _all = [];
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
      setState(() {
        _all = _content.listTopics();
        _loading = false;
      });
    } catch (e) {
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
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.summary.toLowerCase().contains(q) ||
            t.sectionNo.startsWith(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topics = _visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rahbar AI'),
        actions: [
          IconButton(
            tooltip: 'Saved',
            icon: const Icon(Icons.folder_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LibraryScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView(theme)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search topics — e.g. digestion, mixtures',
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _search.clear();
                                      setState(() {});
                                    },
                                  ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: topics.isEmpty
                            ? _noMatch(theme)
                            : ListView.builder(
                                itemCount: topics.length,
                                itemBuilder: (context, i) {
                                  final t = topics[i];
                                  final newChapter =
                                      i == 0 || topics[i - 1].chapter != t.chapter;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (newChapter)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              16, 16, 16, 4),
                                          child: Text(
                                            'Chapter ${t.chapter}',
                                            style: theme.textTheme.labelLarge
                                                ?.copyWith(
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      _tile(t),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _tile(Topic t) => ListTile(
        title: Text(t.title),
        subtitle: t.summary.isEmpty ? null : Text(t.summary, maxLines: 2),
        leading: CircleAvatar(
          radius: 16,
          child: Text(t.sectionNo, style: const TextStyle(fontSize: 10)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TopicScreen(content: _content, topic: t),
          ),
        ),
      );

  /// No topic matched. Rather than a dead end, offer the on-device model — slow, but it
  /// is the thing that makes the app work beyond the shipped curriculum.
  Widget _noMatch(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off,
                  size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text('No topic matches "${_search.text.trim()}"',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'This topic is not in the Class 6 curriculum pack. Rahbar can still '
                'write it on-device, but it takes a few minutes.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate it anyway'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        GenerationScreen(initialTopic: _search.text.trim()),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorView(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('Could not open the content pack',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('$_error',
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
