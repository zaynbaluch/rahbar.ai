import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../content/content_service.dart';
import '../export/pdf_export.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import 'lesson_plan.dart';

/// A 5E lesson plan, rendered section by section — and **swappable**.
///
/// This is the payoff of generating content at build time (ADR-008). Each section ships
/// 2–3 independent variants, so "give me a different activity" is a swap that returns in
/// microseconds. Asking the on-device model to rewrite the plan would cost ~3 minutes, and
/// modification-is-regeneration is exactly the trap this design avoids.
class LessonPlanScreen extends StatefulWidget {
  const LessonPlanScreen({
    super.key,
    required this.content,
    required this.topic,
    required this.plan,
  });

  final ContentService content;
  final Topic topic;
  final LessonPlan plan;

  @override
  State<LessonPlanScreen> createState() => _LessonPlanScreenState();
}

class _LessonPlanScreenState extends State<LessonPlanScreen> {
  final _library = LibraryStore();
  late LessonPlan _plan = widget.plan;
  late final Map<String, List<PlanSection>> _variants =
      widget.content.variantsFor(widget.topic.id);
  bool _saved = false;

  /// Swap one section to its next variant. Everything else on the page is untouched —
  /// the variants are written to stand alone, and the minute budget is fixed in the pack,
  /// so no swap can overrun the 50-minute period.
  void _cycle(String section) {
    final options = _variants[section];
    if (options == null || options.length < 2) return;
    final current = _plan.sectionOf(section);
    final i = options.indexWhere((v) => v.id == current?.id);
    final next = options[(i + 1) % options.length];
    setState(() {
      _plan = LessonPlan(
        topicId: _plan.topicId,
        topic: _plan.topic,
        slos: _plan.slos,
        sections: [
          for (final s in _plan.sections) s.section == section ? next : s,
        ],
      );
      _saved = false;
    });
  }

  Future<void> _save() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _library.save(SavedTest(
      id: now.toString(),
      kind: 'lesson',
      topic: _plan.topic,
      topicId: _plan.topicId,
      createdAtMillis: now,
      contentJson: _plan.toJson(),
    ));
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved to library')));
    }
  }

  Future<void> _print() => Printing.layoutPdf(
        onLayout: (_) => PdfExport.buildLessonPlan(_plan),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final materials = _plan.materials;

    return Scaffold(
      appBar: AppBar(
        title: Text(_plan.topic),
        actions: [
          IconButton(
            tooltip: 'Print / PDF',
            icon: const Icon(Icons.print_outlined),
            onPressed: _print,
          ),
          IconButton(
            tooltip: _saved ? 'Saved' : 'Save',
            icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border),
            onPressed: _saved ? null : _save,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Grade 6 · General Science · one ${_plan.totalMinutes}-minute period',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 12),
            if (materials.isNotEmpty) _materialsCard(theme, materials),
            for (final s in _plan.sections) _sectionCard(theme, s),
          ],
        ),
      ),
    );
  }

  /// Materials are derived from the activity variants actually chosen, so this list always
  /// matches what is on the page — swap the activity and the shopping list follows.
  Widget _materialsCard(ThemeData theme, List<String> materials) => Card(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.shopping_basket_outlined, size: 18),
                const SizedBox(width: 8),
                Text('What to bring', style: theme.textTheme.labelLarge),
              ]),
              const SizedBox(height: 6),
              Text(materials.join(' · '), style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );

  Widget _sectionCard(ThemeData theme, PlanSection s) {
    final options = _variants[s.section] ?? const [];
    final canSwap = options.length > 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    LessonPlan.sectionTitles[s.section] ?? s.section,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (s.minutes > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      label: Text('${s.minutes} min'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (canSwap)
                  IconButton(
                    tooltip: 'Try another (${options.length} options)',
                    icon: const Icon(Icons.autorenew, size: 20),
                    onPressed: () => _cycle(s.section),
                  ),
              ],
            ),
            if (canSwap)
              Text(
                s.variantLabel,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            const SizedBox(height: 8),
            Text(s.body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
