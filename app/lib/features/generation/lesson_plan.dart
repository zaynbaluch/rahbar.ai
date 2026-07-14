/// The 5E lesson-plan model (ADR-006).
///
/// A plan is **assembled**, not generated: the content pack ships 2–3 independent variants
/// of each section, and the app picks one per section (see [ContentService.assemblePlan]).
/// That is what makes "give me a different activity" a swap instead of a 3-minute
/// regeneration, and why two teachers on the same topic do not get the same plan.
///
/// Two invariants make swapping safe, and both are enforced upstream in the pipeline
/// rather than hoped for here:
///  * **Minutes live in the pack, set from `PLAN_MINUTES` in code** — never written by the
///    model — so no combination of variants can overrun the 50-minute period.
///  * **Materials belong to the activity**, not to the plan, so swapping the Explore
///    variant can never leave a stale shopping list behind.
library;

/// One chosen section of a plan (e.g. the `group-work` variant of `explore`).
class PlanSection {
  const PlanSection({
    required this.id,
    required this.section,
    required this.variantLabel,
    required this.minutes,
    required this.body,
    this.materials = const [],
  });

  final String id;
  final String section; // 'engage' | 'explore' | … (see LessonPlan.sectionOrder)
  final String variantLabel; // 'no-materials' | 'group-work' | 'demo-led' | …
  final int minutes; // 0 = untimed (objectives, homework, notes)
  final String body;
  final List<String> materials;

  Map<String, dynamic> toJson() => {
        'id': id,
        'section': section,
        'variantLabel': variantLabel,
        'minutes': minutes,
        'body': body,
        'materials': materials,
      };

  factory PlanSection.fromJson(Map<String, dynamic> j) => PlanSection(
        id: j['id'] as String,
        section: j['section'] as String,
        variantLabel: j['variantLabel'] as String? ?? '',
        minutes: j['minutes'] as int? ?? 0,
        body: j['body'] as String? ?? '',
        materials: (j['materials'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

class LessonPlan {
  const LessonPlan({
    required this.topicId,
    required this.topic,
    required this.slos,
    required this.sections,
  });

  final String topicId;
  final String topic;
  final List<String> slos;
  final List<PlanSection> sections;

  /// Render order — the 5E spine of ADR-006.
  static const List<String> sectionOrder = [
    'objectives',
    'revision_starter',
    'engage',
    'explore',
    'explain',
    'socratic',
    'elaborate',
    'evaluate',
    'differentiation',
    'homework',
    'notes',
  ];

  static const Map<String, String> sectionTitles = {
    'objectives': 'Objectives',
    'revision_starter': 'Revision starter',
    'engage': 'Engage',
    'explore': 'Explore',
    'explain': 'Explain',
    'socratic': 'Socratic questions',
    'elaborate': 'Elaborate',
    'evaluate': 'Evaluate',
    'differentiation': 'Differentiation & multi-grade',
    'homework': 'Homework',
    'notes': 'Notes',
  };

  PlanSection? sectionOf(String name) {
    for (final s in sections) {
      if (s.section == name) return s;
    }
    return null;
  }

  /// The materials list is *derived* from the sections actually chosen, so it always
  /// matches the activity on the page. Storing it separately would let a swap desync it.
  List<String> get materials {
    final seen = <String>{};
    for (final s in sections) {
      for (final m in s.materials) {
        seen.add(m);
      }
    }
    return seen.toList()..sort();
  }

  int get totalMinutes =>
      sections.fold(0, (sum, s) => sum + s.minutes);

  Map<String, dynamic> toJson() => {
        'topicId': topicId,
        'topic': topic,
        'slos': slos,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  factory LessonPlan.fromJson(Map<String, dynamic> j) => LessonPlan(
        topicId: j['topicId'] as String? ?? '',
        topic: j['topic'] as String? ?? '',
        slos: (j['slos'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        sections: (j['sections'] as List? ?? [])
            .map((e) => PlanSection.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
