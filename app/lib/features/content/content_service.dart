import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../curriculum/curriculum_module_registry.dart';
import '../curriculum/teaching_context.dart';
import '../generation/lesson_plan.dart';
import '../generation/mcq_parser.dart';
import 'mcq_option_balancer.dart';

/// A topic from the curriculum catalogue — what the picker shows.
class Topic {
  const Topic({
    required this.id,
    required this.chapter,
    required this.sectionNo,
    required this.title,
    required this.summary,
    required this.slos,
    required this.nItems,
  });

  final String id;
  final int chapter;
  final String sectionNo;
  final String title;
  final String summary;
  final List<String> slos;
  final int nItems; // verified MCQs available for this topic

  bool get hasTest => nItems >= 5;
}

class InsufficientUnusedItemsException implements Exception {
  const InsufficientUnusedItemsException({
    required this.topicTitle,
    required this.availableUnused,
    required this.required,
    required this.totalVerified,
  });

  final String topicTitle;
  final int availableUnused;
  final int required;
  final int totalVerified;

  int get reuseCount => required - availableUnused;

  @override
  String toString() =>
      'Only $availableUnused unused verified questions remain for "$topicTitle".';
}

/// The pre-generated content pack: a verified MCQ item bank plus a library of 5E
/// lesson-plan section variants, built off-device by `pipeline/src/gen_content.py`
/// (see ADR-008).
///
/// On-device generation cost ~3.5 min per test and left the answer key unverifiable —
/// and the OMR grader marks real student papers against that key with no human in the
/// loop (ADR-007). So the content is generated once on a laptop by an 8B model, checked
/// by a second model, and shipped. Here we only **select** from it, which is instant.
///
/// Tests are *sampled* from the bank, not generated; plans are *assembled* from section
/// variants, not generated. The on-device SLM keeps the tail: short open-ended chat, and
/// an escape hatch for topics outside the pack.
class ContentService {
  ContentService({TeachingContext? teachingContext})
    // Keep the public named argument `teachingContext`; an initializing formal
    // would expose the private backing-field name as the constructor API.
    // ignore: prefer_initializing_formals
    : _teachingContext = teachingContext;

  Database? _db;
  CurriculumModuleAssets? _module;
  TeachingContext? _teachingContext;
  final _rng = Random();

  bool get isReady => _db != null;
  String? get activeModuleId => _module?.moduleId;

  /// Copy the selected read-only asset out of the bundle so sqlite3 can open it.
  Future<void> init() => switchContext(_teachingContext);

  /// Open [teachingContext]'s content pack before releasing the current database.
  /// This keeps context changes atomic: a failed asset load can never leave a new
  /// class/subject label backed by the previous module's data.
  Future<void> switchContext(TeachingContext? teachingContext) async {
    final module = CurriculumModuleRegistry.resolve(teachingContext);
    if (_db != null && _module?.moduleId == module.moduleId) {
      _teachingContext = teachingContext;
      return;
    }

    final support = await getApplicationSupportDirectory();
    final safeModuleId = module.moduleId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = p.join(support.path, 'content_pack.$safeModuleId.db');
    final bytes = await rootBundle.load(module.contentAsset);
    await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    final next = sqlite3.open(path, mode: OpenMode.readOnly);

    final previous = _db;
    _db = next;
    _module = module;
    _teachingContext = teachingContext;
    previous?.close();
  }

  void dispose() {
    _db?.close();
    _db = null;
    _module = null;
  }

  String get packVersion {
    final r = _db!.select("SELECT value FROM meta WHERE key = 'pack_version'");
    return r.isEmpty ? '?' : r.first['value'] as String;
  }

  // ---------------------------------------------------------------- topics

  List<Topic> listTopics() {
    final rows = _db!.select(
      'SELECT id, chapter, section_no, title, summary, slos, n_items '
      'FROM topics ORDER BY chapter, section_no',
    );
    return rows.map(_topic).toList();
  }

  Topic? topicById(String id) {
    final rows = _db!.select(
      'SELECT id, chapter, section_no, title, summary, slos, n_items '
      'FROM topics WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _topic(rows.first);
  }

  Topic _topic(Row r) => Topic(
    id: r['id'] as String,
    chapter: r['chapter'] as int,
    sectionNo: r['section_no'] as String,
    title: r['title'] as String,
    summary: (r['summary'] as String?) ?? '',
    slos: ((jsonDecode(r['slos'] as String? ?? '[]')) as List)
        .map((e) => e.toString())
        .toList(),
    nItems: r['n_items'] as int,
  );

  // ---------------------------------------------------------------- MCQ sampling

  /// Draw a test from the item bank. Instant — no model runs.
  ///
  /// Sampling from a bank (rather than generating per request) is how professional
  /// assessment actually works, and it buys two things a live model cannot: the answer
  /// keys were verified before shipping, and [exclude] lets a teacher re-test a class
  /// without repeating questions they have already used.
  ///
  /// [mix] is the target difficulty spread (ADR-007: ~4 easy / 4 medium / 2 hard). If a
  /// band is short, the shortfall is backfilled from the other bands so the teacher still
  /// gets a full paper rather than an error.
  McqTest sampleTest(
    String topicId, {
    int n = 10,
    Map<String, int> mix = const {'easy': 4, 'medium': 4, 'hard': 2},
    Set<String> exclude = const {},
    bool allowReuse = false,
    int? seed,
  }) {
    final topic = topicById(topicId);
    if (topic == null) throw StateError('unknown topic: $topicId');
    final rng = seed == null ? _rng : Random(seed);

    final rows = _db!.select(
      'SELECT id, difficulty, bloom, stem, option_a, option_b, option_c, option_d, answer '
      "FROM mcq_items WHERE topic_id = ? AND verify_status = 'passed'",
      [topicId],
    );
    if (rows.isEmpty) {
      throw StateError(
        'No verified questions are available for "${topic.title}".',
      );
    }

    if (rows.length < n) {
      throw StateError(
        'Only ${rows.length} verified questions are available for "${topic.title}".',
      );
    }
    final target = n;
    final unused = rows
        .where((row) => !exclude.contains(row['id'] as String))
        .toList();
    if (unused.length < target && !allowReuse) {
      throw InsufficientUnusedItemsException(
        topicTitle: topic.title,
        availableUnused: unused.length,
        required: target,
        totalVerified: rows.length,
      );
    }

    // Always use every available unseen item before recycling an older one. This
    // preserves the teacher's expectation that "fresh paper" means fresh wherever
    // the verified bank permits it.
    final picked = _pickRows(unused, target, mix, rng);
    if (picked.length < target) {
      final reused =
          rows
              .where(
                (row) =>
                    exclude.contains(row['id'] as String) &&
                    !picked.contains(row),
              )
              .toList()
            ..shuffle(rng);
      picked.addAll(reused.take(target - picked.length));
    }
    picked.shuffle(rng);

    // The source bank has a strong answer-position bias. Reposition correct answers
    // into balanced A/B/C/D targets for this paper, except where an option explicitly
    // depends on its label or on being "above" another option.
    final targets = McqOptionBalancer.targetPositions(picked.length, rng);
    final questions = <McqQuestion>[];
    final reusedItemIds = <String>{};
    for (var i = 0; i < picked.length && i < target; i++) {
      final row = picked[i];
      final itemId = row['id'] as String;
      final sourceOptions = <String, String>{
        'A': row['option_a'] as String,
        'B': row['option_b'] as String,
        'C': row['option_c'] as String,
        'D': row['option_d'] as String,
      };
      final balanced = McqOptionBalancer.placeCorrectAt(
        options: sourceOptions,
        answer: row['answer'] as String,
        targetAnswer: targets[i],
        random: rng,
      );
      if (exclude.contains(itemId)) reusedItemIds.add(itemId);
      questions.add(
        McqQuestion(
          number: i + 1,
          difficulty: row['difficulty'] as String,
          text: row['stem'] as String,
          options: balanced.options,
          answer: balanced.answer,
          itemId: itemId,
        ),
      );
    }
    return McqTest(
      topic: topic.title,
      questions: questions,
      expectedCount: target,
      reusedItemIds: reusedItemIds,
    );
  }

  List<Row> _pickRows(
    List<Row> pool,
    int target,
    Map<String, int> mix,
    Random rng,
  ) {
    final byBand = <String, List<Row>>{};
    for (final row in pool) {
      byBand.putIfAbsent(row['difficulty'] as String, () => []).add(row);
    }
    for (final list in byBand.values) {
      list.shuffle(rng);
    }

    final picked = <Row>[];
    for (final entry in mix.entries) {
      if (picked.length >= target) break;
      final band = byBand[entry.key] ?? const <Row>[];
      picked.addAll(band.take(min(entry.value, target - picked.length)));
    }
    if (picked.length < target) {
      final rest = pool.where((row) => !picked.contains(row)).toList()
        ..shuffle(rng);
      picked.addAll(rest.take(target - picked.length));
    }
    return picked;
  }

  // ---------------------------------------------------------------- plan assembly

  /// Build a full 5E lesson plan by choosing one variant per section — instant, and with
  /// ~50 distinct combinations per topic, two teachers do not get the same plan.
  ///
  /// [prefer] pins a section to a named variant (this is what "swap this activity" uses).
  LessonPlan assemblePlan(
    String topicId, {
    Map<String, String> prefer = const {},
    int? seed,
  }) {
    final topic = topicById(topicId);
    if (topic == null) throw StateError('unknown topic: $topicId');
    final rng = seed == null ? _rng : Random(seed);

    final variants = variantsFor(topicId);
    final sections = <PlanSection>[];
    for (final section in LessonPlan.sectionOrder) {
      final options = variants[section];
      if (options == null || options.isEmpty) continue;
      final wanted = prefer[section];
      final chosen = options.firstWhere(
        (v) => v.variantLabel == wanted,
        orElse: () => options[rng.nextInt(options.length)],
      );
      sections.add(chosen);
    }
    return LessonPlan(
      topicId: topicId,
      topic: topic.title,
      slos: topic.slos,
      sections: sections,
    );
  }

  /// Every variant of every section for a topic, keyed by section — the swap menu.
  Map<String, List<PlanSection>> variantsFor(String topicId) {
    final rows = _db!.select(
      'SELECT id, section, variant_label, minutes, body, materials '
      'FROM plan_sections WHERE topic_id = ?',
      [topicId],
    );
    final out = <String, List<PlanSection>>{};
    for (final r in rows) {
      final s = PlanSection(
        id: r['id'] as String,
        section: r['section'] as String,
        variantLabel: r['variant_label'] as String,
        minutes: r['minutes'] as int,
        body: r['body'] as String,
        materials: ((jsonDecode(r['materials'] as String? ?? '[]')) as List)
            .map((e) => e.toString())
            .toList(),
      );
      out.putIfAbsent(s.section, () => []).add(s);
    }
    return out;
  }
}
