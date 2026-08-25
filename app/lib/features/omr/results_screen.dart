import 'package:flutter/material.dart';

import '../../core/storage/local_store_load.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/empty_state.dart';
import '../../design_system/components/recovered_data_notice.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../library/library_store.dart';
import '../library/saved_test.dart';
import 'gradebook_store.dart';
import 'graded_result.dart';
import 'grading_screen.dart';

class QuestionPerformance {
  const QuestionPerformance({
    required this.questionNumber,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.correctOption,
    required this.distribution,
  });
  final int questionNumber;
  final int correct;
  final int wrong;
  final int blank;
  final String correctOption;
  final Map<String, int> distribution;
  int get total => correct + wrong;
  int get percentCorrect => total == 0 ? 0 : (100 * correct / total).round();
}

List<QuestionPerformance> calculateQuestionPerformance(
  List<GradedResult> results,
) {
  if (results.isEmpty) return const [];
  final maxQuestions = results
      .map((r) => r.total)
      .fold<int>(0, (a, b) => a > b ? a : b);
  final out = <QuestionPerformance>[];
  for (var i = 0; i < maxQuestions; i++) {
    final distribution = <String, int>{'A': 0, 'B': 0, 'C': 0, 'D': 0};
    var blank = 0;
    var correct = 0;
    String key = '';
    var participants = 0;
    for (final result in results) {
      if (i >= result.total) continue;
      participants++;
      final marks = result.marks.split('|');
      final keys = result.correctAnswers.split('|');
      final mark = i < marks.length ? marks[i] : '';
      final answer = i < keys.length ? keys[i] : '';
      if (key.isEmpty && answer.isNotEmpty) key = answer;
      if (mark.isEmpty) {
        blank++;
      } else if (distribution.containsKey(mark)) {
        distribution[mark] = distribution[mark]! + 1;
      }
      if (mark.isNotEmpty && mark == answer) correct++;
    }
    out.add(
      QuestionPerformance(
        questionNumber: i + 1,
        correct: correct,
        wrong: participants - correct,
        blank: blank,
        correctOption: key,
        distribution: distribution,
      ),
    );
  }
  out.sort((a, b) {
    final wrong = b.wrong.compareTo(a.wrong);
    return wrong != 0 ? wrong : a.questionNumber.compareTo(b.questionNumber);
  });
  return out;
}

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    required this.testId,
    required this.topic,
    this.store,
    this.libraryStore,
  });
  final String testId;
  final String topic;
  final GradebookStore? store;
  final LibraryStore? libraryStore;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsData {
  const _ResultsData({required this.load, this.savedTest});
  final LocalStoreLoad<GradedResult> load;
  final SavedTest? savedTest;
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final GradebookStore _store = widget.store ?? GradebookStore();
  late final LibraryStore _library = widget.libraryStore ?? LibraryStore();
  late Future<_ResultsData> _future = _load();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<_ResultsData> _load() async {
    final load = await _store.loadForTest(widget.testId);
    final saved = await _library.load();
    SavedTest? source;
    for (final item in saved.items) {
      if (item.kind == 'mcq' && item.id == widget.testId) {
        source = item;
        break;
      }
    }
    return _ResultsData(load: load, savedTest: source);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _delete(GradedResult result) async {
    await _store.delete(result.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Class Results')),
    body: SafeArea(
      child: FutureBuilder<_ResultsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return BayazEmptyState(
              asset: 'assets/ui/illustrations/no_search_results.webp',
              title: 'Could not load these results',
              message: 'The saved results could not be read from this device.',
              action: FilledButton(
                onPressed: _reload,
                child: const Text('Try again'),
              ),
            );
          }
          final data = snapshot.data!;
          final results = data.load.items;
          if (results.isEmpty) {
            return const BayazEmptyState(
              asset: 'assets/ui/illustrations/empty_results.webp',
              title: 'No results yet',
              message:
                  'Grade answer sheets from this test to build the class summary.',
            );
          }
          final first = results.first;
          final contextLabel = [
            first.teachingContext?.className,
            first.teachingContext?.subjectName,
          ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
          final average =
              results.map((r) => r.pct).reduce((a, b) => a + b) /
              results.length;
          final high = results
              .map((r) => r.correct)
              .reduce((a, b) => a > b ? a : b);
          final low = results
              .map((r) => r.correct)
              .reduce((a, b) => a < b ? a : b);
          final total = first.total;
          final performance = calculateQuestionPerformance(results);
          final query = _search.text.trim().toLowerCase();
          final visible = results
              .where(
                (result) =>
                    query.isEmpty ||
                    result.studentName.toLowerCase().contains(query),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              if (data.load.recoveredCorruptData) ...[
                RecoveredDataNotice(
                  count: data.load.recoveredFiles,
                  itemLabel: 'grading result',
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                widget.topic,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (contextLabel.isNotEmpty) Text(contextLabel),
              Text(
                _date(first.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              _StatsGrid(
                students: results.length,
                average: average.round(),
                high: high,
                low: low,
                total: total,
              ),
              if (performance.any((item) => item.wrong > 0)) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Needs attention',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final item
                    in performance.where((item) => item.wrong > 0).take(3)) ...[
                  BayazCard(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => QuestionPerformanceScreen(
                          topic: widget.topic,
                          performance: item,
                          stem: _stemFor(data.savedTest, item.questionNumber),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Question ${item.questionNumber}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${item.wrong} ${item.wrong == 1 ? 'student got' : 'students got'} it wrong',
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('Students', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search students',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final result in visible) ...[
                Dismissible(
                  key: ValueKey(result.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmDelete(result),
                  onDismissed: (_) => _delete(result),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: AppSpacing.lg),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Icon(Icons.delete_outline),
                  ),
                  child: BayazCard(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StudentResultScreen(result: result),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            result.studentName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${result.correct}/${result.total}   ${result.pct}%',
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (data.savedTest != null) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GradingScreen(
                        test: data.savedTest!.toMcqTest(),
                        teachingContext: data.savedTest!.teachingContext,
                      ),
                    ),
                  ),
                  child: const Text('Grade more papers'),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );

  Future<bool> _confirmDelete(GradedResult result) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this result?'),
          content: Text(
            '${result.studentName}’s saved score will be removed from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

String? _stemFor(SavedTest? saved, int questionNumber) {
  if (saved == null) return null;
  try {
    final test = saved.toMcqTest();
    for (final question in test.questions) {
      if (question.number == questionNumber) return question.text;
    }
  } catch (_) {}
  return null;
}

String _date(DateTime date) => '${date.day}/${date.month}/${date.year}';

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.students,
    required this.average,
    required this.high,
    required this.low,
    required this.total,
  });
  final int students;
  final int average;
  final int high;
  final int low;
  final int total;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - AppSpacing.sm) / 2;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          _Stat(width: width, value: '$students', label: 'Students'),
          _Stat(width: width, value: '$average%', label: 'Average'),
          _Stat(width: width, value: '$high/$total', label: 'Highest'),
          _Stat(width: width, value: '$low/$total', label: 'Lowest'),
        ],
      );
    },
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.width, required this.value, required this.label});
  final double width;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => BayazCard(
    child: SizedBox(
      width: width - 2 * AppSpacing.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: AppColors.primary),
          ),
          Text(label),
        ],
      ),
    ),
  );
}

class QuestionPerformanceScreen extends StatelessWidget {
  const QuestionPerformanceScreen({
    super.key,
    required this.topic,
    required this.performance,
    this.stem,
  });
  final String topic;
  final QuestionPerformance performance;
  final String? stem;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Question ${performance.questionNumber}')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(topic, style: Theme.of(context).textTheme.titleLarge),
          if (stem != null && stem!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(stem!),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            '${performance.wrong} of ${performance.total} students got this question wrong.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${performance.percentCorrect}%',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(color: AppColors.primary),
          ),
          const Text('answered correctly'),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Correct answer: ${performance.correctOption.isEmpty ? '—' : performance.correctOption}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Student answers',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final option in const ['A', 'B', 'C', 'D'])
            Text(
              '$option    ${performance.distribution[option] ?? 0} students',
            ),
          if (performance.blank > 0) Text('Blank    ${performance.blank}'),
        ],
      ),
    ),
  );
}

class StudentResultScreen extends StatelessWidget {
  const StudentResultScreen({super.key, required this.result});
  final GradedResult result;
  @override
  Widget build(BuildContext context) {
    final contextLabel = [
      result.teachingContext?.className,
      result.teachingContext?.subjectName,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    final marks = result.marks.split('|');
    final keys = result.correctAnswers.split('|');
    return Scaffold(
      appBar: AppBar(title: Text(result.studentName)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              result.testTopic,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (contextLabel.isNotEmpty) Text(contextLabel),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '${result.correct} / ${result.total}',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: AppColors.primary),
            ),
            Text(
              '${result.pct}%',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${result.correct} correct · ${result.total - result.correct} incorrect',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Answers', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < result.total; i++)
              _StudentAnswerRow(
                number: i + 1,
                mark: i < marks.length && marks[i].isNotEmpty
                    ? marks[i]
                    : 'Blank',
                keyAnswer: i < keys.length ? keys[i] : '',
              ),
          ],
        ),
      ),
    );
  }
}

class _StudentAnswerRow extends StatelessWidget {
  const _StudentAnswerRow({
    required this.number,
    required this.mark,
    required this.keyAnswer,
  });
  final int number;
  final String mark;
  final String keyAnswer;
  @override
  Widget build(BuildContext context) {
    final correct = mark == keyAnswer && mark != 'Blank';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: correct
                ? AppColors.success
                : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('Q$number'),
          const Spacer(),
          Text(mark),
          if (!correct) ...[
            const SizedBox(width: AppSpacing.sm),
            Text('Key: $keyAnswer'),
          ],
        ],
      ),
    );
  }
}
