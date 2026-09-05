import 'lesson_plan.dart';

class LessonPlanParseResult {
  const LessonPlanParseResult({
    required this.plan,
    required this.missingSections,
  });

  final LessonPlan plan;
  final List<String> missingSections;
  bool get isComplete => missingSections.isEmpty;
}

/// Parses the strict Markdown contract in assets/prompts/lesson_plan.md into the
/// same model used by pre-generated plans. It is deliberately tolerant of case,
/// punctuation, bullets, and model-added timing text, but it never invents a
/// missing section.
abstract final class LessonPlanParser {
  static final RegExp _header = RegExp(r'^#{2,4}\s+(.+?)\s*$', caseSensitive: false);
  static final RegExp _minutes = RegExp(r'\((\d{1,3})\s*min(?:ute)?s?\)', caseSensitive: false);

  static const _aliases = <String, String>{
    'objectives': 'objectives',
    'learning objectives': 'objectives',
    'revision starter': 'revision_starter',
    'starter': 'revision_starter',
    'engage': 'engage',
    'explore': 'explore',
    'explain': 'explain',
    'socratic questions': 'socratic',
    'questions': 'socratic',
    'elaborate': 'elaborate',
    'evaluate': 'evaluate',
    'assessment': 'evaluate',
    'differentiation': 'differentiation',
    'differentiation & multi-grade': 'differentiation',
    'homework': 'homework',
    'notes': 'notes',
    'materials': '_materials',
    'resources': '_materials',
  };

  static LessonPlanParseResult parse(
    String markdown, {
    required String topic,
    String topicId = '',
  }) {
    final bodies = <String, List<String>>{};
    final minutes = <String, int>{};
    String? current;

    for (final rawLine in markdown.replaceAll('\r\n', '\n').split('\n')) {
      final match = _header.firstMatch(rawLine.trim());
      if (match != null) {
        final rawTitle = match.group(1)!.trim();
        final withoutMinutes = rawTitle.replaceAll(_minutes, '').trim();
        final normalized = withoutMinutes
            .toLowerCase()
            .replaceAll(RegExp(r'[:\-–—]+$'), '')
            .trim();
        current = _aliases[normalized];
        if (current != null) {
          bodies.putIfAbsent(current, () => <String>[]);
          final minuteMatch = _minutes.firstMatch(rawTitle);
          if (minuteMatch != null) {
            minutes[current] = int.tryParse(minuteMatch.group(1)!) ?? 0;
          }
        }
        continue;
      }
      if (current != null) bodies[current]!.add(rawLine);
    }

    final materials = _listItems(_body(bodies['_materials'] ?? const []));
    final sections = <PlanSection>[];
    for (final section in LessonPlan.sectionOrder) {
      final body = _body(bodies[section] ?? const []);
      if (body.isEmpty) continue;
      sections.add(PlanSection(
        id: 'custom-$section',
        section: section,
        variantLabel: 'custom-ai',
        minutes: minutes[section] ?? _defaultMinutes(section),
        body: body,
        materials: section == 'explore' ? materials : const [],
      ));
    }

    final objectives = _listItems(_body(bodies['objectives'] ?? const []));
    final required = <String>[
      'objectives',
      'engage',
      'explore',
      'explain',
      'evaluate',
      'homework',
    ];
    final present = sections.map((section) => section.section).toSet();
    return LessonPlanParseResult(
      plan: LessonPlan(
        topicId: topicId,
        topic: topic,
        slos: objectives,
        sections: sections,
      ),
      missingSections: required.where((section) => !present.contains(section)).toList(),
    );
  }

  static String _body(List<String> lines) {
    final result = [...lines];
    while (result.isNotEmpty && result.first.trim().isEmpty) {
      result.removeAt(0);
    }
    while (result.isNotEmpty && result.last.trim().isEmpty) {
      result.removeLast();
    }
    return result.join('\n').trim();
  }

  static List<String> _listItems(String body) => body
      .split('\n')
      .map((line) => line.trim().replaceFirst(RegExp(r'^[-*•]\s*'), ''))
      .where((line) => line.isNotEmpty && line.toLowerCase() != 'none needed')
      .toList(growable: false);

  static int _defaultMinutes(String section) => switch (section) {
        'revision_starter' => 5,
        'engage' => 5,
        'explore' => 12,
        'explain' => 12,
        'elaborate' => 8,
        'evaluate' => 8,
        _ => 0,
      };
}
