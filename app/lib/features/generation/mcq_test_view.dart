import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../export/pdf_export.dart';
import '../omr/grading_screen.dart';
import 'mcq_parser.dart';

/// Reusable display for a parsed [McqTest]: a summary banner (question count,
/// show/hide answer key, export PDF, optional save) followed by question cards.
/// Shared by the live generation screen and the saved-test viewer so both render
/// identically. Manages the answer-reveal toggle internally.
class McqTestView extends StatefulWidget {
  const McqTestView({super.key, required this.test, this.onSave, this.saved = false});

  final McqTest test;

  /// Optional save action (shown only on freshly generated tests).
  final VoidCallback? onSave;

  /// When true, the save control shows as already-saved (disabled check).
  final bool saved;

  @override
  State<McqTestView> createState() => _McqTestViewState();
}

class _McqTestViewState extends State<McqTestView> {
  bool _showAnswers = false;

  Future<void> _export() async {
    final bytes = await PdfExport.build(widget.test);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Rahbar-${PdfExport.testId(widget.test.topic)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final test = widget.test;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          test: test,
          showAnswers: _showAnswers,
          onToggle: () => setState(() => _showAnswers = !_showAnswers),
          onExport: _export,
          onSave: widget.onSave,
          saved: widget.saved,
        ),
        const SizedBox(height: 8),
        for (final q in test.questions)
          _QuestionCard(q: q, showAnswer: _showAnswers),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.test,
    required this.showAnswers,
    required this.onToggle,
    required this.onExport,
    required this.onSave,
    required this.saved,
  });

  final McqTest test;
  final bool showAnswers;
  final VoidCallback onToggle;
  final VoidCallback onExport;
  final VoidCallback? onSave;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = test.completeCount == test.count;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(complete ? Icons.check_circle : Icons.info_outline,
                    color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${test.count} questions'
                    '${complete ? '' : ' · ${test.completeCount} complete'}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
                Text('ID ${PdfExport.testId(test.topic)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onSave != null)
                  TextButton.icon(
                    onPressed: saved ? null : onSave,
                    icon: Icon(saved ? Icons.bookmark_added : Icons.bookmark_add_outlined),
                    label: Text(saved ? 'Saved' : 'Save'),
                  ),
                TextButton.icon(
                  onPressed: onToggle,
                  icon: Icon(showAnswers ? Icons.visibility_off : Icons.visibility),
                  label: Text(showAnswers ? 'Hide key' : 'Show key'),
                ),
                IconButton(
                  tooltip: 'Export / print PDF',
                  onPressed: onExport,
                  icon: const Icon(Icons.picture_as_pdf),
                ),
                IconButton(
                  tooltip: 'Grade answer sheets',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GradingScreen(test: test),
                  )),
                  icon: const Icon(Icons.grading),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.q, required this.showAnswer});

  final McqQuestion q;
  final bool showAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Q${q.number}. ',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(q.text.isEmpty ? '(missing question)' : q.text,
                      style: theme.textTheme.titleSmall),
                ),
                if (q.difficulty.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Chip(
                      label: Text(q.difficulty),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final letter in const ['A', 'B', 'C', 'D'])
              if (q.options.containsKey(letter))
                _OptionRow(
                  letter: letter,
                  text: q.options[letter]!,
                  correct: showAnswer && q.answer == letter,
                ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.letter,
    required this.text,
    required this.correct,
  });

  final String letter;
  final String text;
  final bool correct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: correct ? theme.colorScheme.tertiaryContainer : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$letter) ',
              style: TextStyle(
                  fontWeight: correct ? FontWeight.bold : FontWeight.normal)),
          Expanded(child: Text(text)),
          if (correct)
            Icon(Icons.check, size: 18, color: theme.colorScheme.onTertiaryContainer),
        ],
      ),
    );
  }
}
