import 'package:flutter/material.dart';

import '../generation/lesson_plan_view.dart';
import '../generation/mcq_test_view.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import 'content_service.dart';

/// One topic: draw a test or assemble a lesson plan. Both are **instant** — the content
/// was generated and verified off-device (ADR-008), so nothing runs a model here.
///
/// The old flow spent ~3.5 min per artifact and throttled hard on a second run. This one
/// has no dead air, which is what makes the demo work.
class TopicScreen extends StatefulWidget {
  const TopicScreen({super.key, required this.content, required this.topic});

  final ContentService content;
  final Topic topic;

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  final _library = LibraryStore();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.topic;

    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (t.summary.isNotEmpty)
              Text(t.summary, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            if (t.slos.isNotEmpty) ...[
              Text('Learning outcomes', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final s in t.slos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(s, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
            ],
            FilledButton.icon(
              icon: const Icon(Icons.menu_book),
              label: const Text('Lesson plan'),
              onPressed: _openPlan,
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.checklist),
              label: Text(t.hasTest
                  ? 'Make a 10-question test'
                  : 'Make a test (${t.nItems} questions available)'),
              onPressed: t.nItems == 0 ? null : _openTest,
            ),
            const SizedBox(height: 12),
            Text(
              '${t.nItems} verified questions in the bank · '
              'Chapter ${t.chapter}, section ${t.sectionNo}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  void _openPlan() {
    final plan = widget.content.assemblePlan(widget.topic.id);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LessonPlanScreen(
        content: widget.content,
        topic: widget.topic,
        plan: plan,
      ),
    ));
  }

  /// Draw a fresh paper. Questions already used for this topic are excluded, so a second
  /// test on the same topic is genuinely a different test rather than a reshuffle.
  Future<void> _openTest() async {
    final used = await _usedItemIds(widget.topic.id);
    if (!mounted) return;
    try {
      final test = widget.content.sampleTest(widget.topic.id, exclude: used);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(widget.topic.title)),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: McqTestView(
                test: test,
                onSave: () => _saveTest(test),
                saved: false,
              ),
            ),
          ),
        ),
      ));
    } on StateError catch (e) {
      if (!mounted) return;
      // The bank is exhausted for this topic — say so plainly rather than silently
      // repeating questions the teacher has already used.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Every bank item this teacher has already put on a paper for this topic.
  Future<Set<String>> _usedItemIds(String topicId) async {
    final saved = await _library.list();
    final used = <String>{};
    for (final s in saved) {
      if (s.kind == 'mcq' && s.topicId == topicId && s.contentJson != null) {
        used.addAll(s.toMcqTest().itemIds);
      }
    }
    return used;
  }

  Future<void> _saveTest(dynamic test) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _library.save(SavedTest(
      id: now.toString(),
      kind: 'mcq',
      topic: widget.topic.title,
      topicId: widget.topic.id,
      createdAtMillis: now,
      contentJson: test.toJson() as Map<String, dynamic>,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved to library')));
    }
  }
}
