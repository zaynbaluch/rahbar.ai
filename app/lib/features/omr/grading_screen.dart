import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../design_system/components/frame_animation.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../curriculum/recent_work_store.dart';
import '../curriculum/teaching_context.dart';
import '../export/pdf_export.dart';
import '../generation/mcq_parser.dart';
import 'gradebook_store.dart';
import 'graded_result.dart';
import 'image_pick_recovery.dart';
import 'omr_diagnostics.dart';
import 'omr_grader.dart';
import 'omr_image_processor.dart';
import 'results_screen.dart';
import 'student_name_sequence.dart';

class GradingScreen extends StatefulWidget {
  const GradingScreen({
    super.key,
    required this.test,
    this.initialImagePath,
    this.recoveryStore,
    this.picker,
    this.imageProcessor,
    this.gradebookStore,
    this.teachingContext,
    this.initialResult,
    this.recentWorkStore,
  });

  final McqTest test;
  final String? initialImagePath;
  final PendingImagePickStore? recoveryStore;
  final ImagePicker? picker;
  final OmrImageProcessor? imageProcessor;
  final GradebookStore? gradebookStore;
  final TeachingContext? teachingContext;
  final OmrResult? initialResult;
  final RecentWorkStore? recentWorkStore;

  @override
  State<GradingScreen> createState() => _GradingScreenState();
}

class _GradingScreenState extends State<GradingScreen> {
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  late final PendingImagePickStore _recoveryStore =
      widget.recoveryStore ?? PendingImagePickStore();
  late final OmrImageProcessor _imageProcessor =
      widget.imageProcessor ?? OmrImageProcessor();
  late final GradebookStore _gradebook =
      widget.gradebookStore ?? GradebookStore();
  late final RecentWorkStore _recentWork =
      widget.recentWorkStore ?? RecentWorkStore();
  late final Future<void> _studentNamesReady;
  final Set<String> _studentNames = {};
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  OmrResult? _result;
  OmrDiagnostics? _diagnostics;
  bool _saved = false;
  bool _saving = false;
  int _nextStudentNumber = 1;

  String get _testId => PdfExport.testId(widget.test);

  @override
  void initState() {
    super.initState();
    _studentNamesReady = _loadExistingStudentNames();
    unawaited(_recentWork.setActiveGrading(_testId).catchError((_) {}));
    final initialPath = widget.initialImagePath;
    final initialResult = widget.initialResult;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _studentNamesReady;
      if (!mounted) return;
      if (initialResult != null) {
        setState(() {
          _diagnostics = initialResult.diagnostics;
          if (initialResult.fiducialsFound &&
              initialResult.diagnostics?.status != OmrScanStatus.rejected) {
            _result = initialResult;
            _name.text = 'Student $_nextStudentNumber';
          } else {
            _result = null;
            _error = 'Couldn’t read this answer sheet';
          }
        });
      } else if (initialPath != null) {
        await _gradePath(initialPath, clearRecovery: true);
      }
    });
  }

  Future<void> _loadExistingStudentNames() async {
    final existing = await _gradebook.listForTest(_testId);
    _studentNames
      ..clear()
      ..addAll(existing.map((result) => result.studentName));
    _nextStudentNumber = StudentNameSequence.nextNumber(_studentNames);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _grade(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _diagnostics = null;
      _saved = false;
    });
    try {
      await _recoveryStore.begin(
        widget.test,
        source,
        teachingContext: widget.teachingContext,
      );
      final shot = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (shot == null) {
        await _recoveryStore.clear();
        return;
      }
      await _gradePath(shot.path, clearRecovery: true, alreadyBusy: true);
    } catch (_) {
      await _recoveryStore.clear();
      if (mounted) setState(() => _error = 'Couldn’t read this answer sheet');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gradePath(
    String path, {
    required bool clearRecovery,
    bool alreadyBusy = false,
  }) async {
    if (_busy && !alreadyBusy) return;
    if (!alreadyBusy) {
      setState(() {
        _busy = true;
        _error = null;
        _result = null;
        _diagnostics = null;
        _saved = false;
      });
    }
    try {
      await _studentNamesReady;
      final bytes = await File(path).readAsBytes();
      final result = await _imageProcessor.process(bytes, widget.test);
      if (!result.fiducialsFound ||
          result.diagnostics?.status == OmrScanStatus.rejected) {
        if (mounted) setState(() => _diagnostics = result.diagnostics);
        throw const FormatException('markers');
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _diagnostics = result.diagnostics;
        _name.text = 'Student $_nextStudentNumber';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t read this answer sheet');
    } finally {
      if (clearRecovery) await _recoveryStore.clear();
      if (!alreadyBusy && mounted) setState(() => _busy = false);
    }
  }

  void _setMark(int questionNumber, String? mark) {
    final current = _result;
    if (current == null || _saved) return;
    setState(() => _result = current.withMark(questionNumber, mark));
  }

  Future<void> _saveResult() async {
    final result = _result;
    if (result == null || _saved || _saving || result.needsReview > 0) return;
    final typedName = _name.text.trim();
    final studentName = typedName.isEmpty
        ? 'Student $_nextStudentNumber'
        : typedName;
    setState(() => _saving = true);
    try {
      await _gradebook.save(
        GradedResult.fromGrading(
          testId: _testId,
          testTopic: widget.test.topic,
          studentName: studentName,
          result: result,
          teachingContext: widget.teachingContext,
        ),
      );
      try {
        await _recentWork.setActiveGrading(_testId);
      } catch (_) {
        // The result itself is already safely persisted.
      }
      if (!mounted) return;
      setState(() {
        _saved = true;
        _studentNames.add(studentName);
        _nextStudentNumber = StudentNameSequence.nextNumber(_studentNames);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _gradeNext() {
    setState(() {
      _result = null;
      _saved = false;
      _error = null;
      _diagnostics = null;
      _name.text = 'Student $_nextStudentNumber';
    });
  }

  Future<void> _openResults() async {
    await _recentWork.clearActiveGrading();
    await _recentWork.update(RecentWorkReference(type: 'results', id: _testId));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          testId: _testId,
          topic: widget.test.topic,
          recentWorkStore: _recentWork,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Grade Papers')),
      body: SafeArea(
        child: _busy
            ? const _ReadingState()
            : _saved && result != null
            ? _SavedState(
                studentName: _name.text.trim(),
                result: result,
                onNext: _gradeNext,
                onResults: _openResults,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                children: [
                  _GradingHeader(
                    test: widget.test,
                    teachingContext: widget.teachingContext,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (result == null && _error == null) ...[
                    const _CaptureGuide(),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => _grade(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Open camera'),
                    ),
                    TextButton.icon(
                      onPressed: () => _grade(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose image'),
                    ),
                  ],
                  if (_error != null) ...[
                    _ReadError(
                      diagnostics: _diagnostics,
                      onRetake: () => _grade(ImageSource.camera),
                      onChoose: () => _grade(ImageSource.gallery),
                    ),
                    if (_diagnostics != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _DiagnosticsCard(diagnostics: _diagnostics!),
                    ],
                  ],
                  if (result != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Student name or roll number',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ResultSummary(result: result),
                    if (_diagnostics != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _DiagnosticsCard(diagnostics: _diagnostics!),
                    ],
                    if (result.needsReview > 0) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        '${result.needsReview} ${result.needsReview == 1 ? 'answer needs' : 'answers need'} your review',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final question in result.questions.where(
                        (q) =>
                            !q.reviewed &&
                            (q.marked == null || q.confidence < .20),
                      )) ...[
                        _UncertainAnswerCard(
                          question: question,
                          onChanged: (mark) => _setMark(question.number, mark),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Question review',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    BayazCard(
                      child: Column(
                        children: [
                          for (final question in result.questions)
                            _QuestionResultRow(question: question),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: result.needsReview == 0 && !_saving
                          ? _saveResult
                          : null,
                      child: Text(_saving ? 'Saving…' : 'Save result'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _GradingHeader extends StatelessWidget {
  const _GradingHeader({required this.test, required this.teachingContext});
  final McqTest test;
  final TeachingContext? teachingContext;
  @override
  Widget build(BuildContext context) {
    final label = [
      teachingContext?.className,
      teachingContext?.subjectName,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${test.topic} · ${test.count} questions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(label),
        ],
      ],
    );
  }
}

class _CaptureGuide extends StatelessWidget {
  const _CaptureGuide();
  @override
  Widget build(BuildContext context) => BayazCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/ui/grading/omr_capture_guide.webp',
            width: double.infinity,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Keep all four markers visible and the answer box in frame. Avoid shadows and hold the phone parallel to the paper.',
        ),
      ],
    ),
  );
}

class _ReadingState extends StatelessWidget {
  const _ReadingState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BayazFrameAnimation(name: 'scanning_answers', size: 150, loop: true),
        SizedBox(height: AppSpacing.sm),
        Text('Reading the answers…'),
        SizedBox(height: AppSpacing.sm),
        SizedBox(width: 180, child: LinearProgressIndicator()),
      ],
    ),
  );
}

class _ReadError extends StatelessWidget {
  const _ReadError({
    required this.onRetake,
    required this.onChoose,
    this.diagnostics,
  });
  final VoidCallback onRetake;
  final VoidCallback onChoose;
  final OmrDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    final guidance = diagnostics?.failureCode == OmrFailureCode.templateMismatch
        ? 'This image doesn’t match the Bayaz answer grid. Use the answer box from a test PDF created by Bayaz.'
        : 'Make sure all four markers are visible and avoid shadows over the answer box.';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 44),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Couldn’t read this answer sheet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(guidance, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onRetake, child: const Text('Retake')),
          TextButton(onPressed: onChoose, child: const Text('Choose image')),
        ],
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.result});
  final OmrResult result;
  @override
  Widget build(BuildContext context) {
    final pct = result.total == 0
        ? 0
        : (100 * result.correct / result.total).round();
    final incorrect = result.total - result.correct - result.blank;
    return BayazCard(
      color: const Color(0xFFF3F8FF),
      child: Column(
        children: [
          Text(
            '${result.correct} / ${result.total}',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(color: AppColors.primary),
          ),
          Text('$pct%', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${result.correct} correct · $incorrect incorrect${result.blank == 0 ? '' : ' · ${result.blank} blank'}',
          ),
        ],
      ),
    );
  }
}

class _UncertainAnswerCard extends StatelessWidget {
  const _UncertainAnswerCard({required this.question, required this.onChanged});
  final OmrQuestion question;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => BayazCard(
    key: ValueKey('uncertain-${question.number}'),
    borderColor: Theme.of(context).colorScheme.primary,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Question ${question.number}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text('Bayaz couldn’t clearly read this answer.'),
        const SizedBox(height: AppSpacing.sm),
        const Text('What did the student mark?'),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final option in const ['A', 'B', 'C', 'D'])
              ChoiceChip(
                label: Text(option),
                selected: false,
                onSelected: (_) => onChanged(option),
              ),
            ChoiceChip(
              label: const Text('Blank'),
              selected: false,
              onSelected: (_) => onChanged(null),
            ),
          ],
        ),
      ],
    ),
  );
}

class _QuestionResultRow extends StatelessWidget {
  const _QuestionResultRow({required this.question});
  final OmrQuestion question;
  @override
  Widget build(BuildContext context) {
    final correct = question.isRight;
    final marked = question.marked ?? 'Blank';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: correct
                ? AppColors.success
                : Theme.of(context).colorScheme.error,
            size: 21,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('Q${question.number}'),
          const Spacer(),
          Text(marked),
          if (!correct) ...[
            const SizedBox(width: AppSpacing.sm),
            Text('Key: ${question.correct ?? '—'}'),
          ],
        ],
      ),
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({required this.diagnostics});

  final OmrDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final totalMs = diagnostics.stageTimingsMs['total'];
    final rejectionNote =
        diagnostics.failureCode == OmrFailureCode.templateMismatch
        ? diagnostics.templateNote
        : diagnostics.registrationNote;
    final subtitle = diagnostics.status == OmrScanStatus.rejected
        ? '${diagnostics.failureCode.name} · $rejectionNote'
        : '${diagnostics.markerCandidateCount} marker candidates${totalMs == null ? '' : ' · ${totalMs}ms'}';
    return BayazCard(
      child: ExpansionTile(
        initiallyExpanded: diagnostics.status == OmrScanStatus.rejected,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        title: const Text('Scan diagnostics'),
        subtitle: Text(subtitle),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              diagnostics.toReport(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: diagnostics.toReport()),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Scan diagnostics copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy diagnostics'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedState extends StatelessWidget {
  const _SavedState({
    required this.studentName,
    required this.result,
    required this.onNext,
    required this.onResults,
  });
  final String studentName;
  final OmrResult result;
  final VoidCallback onNext;
  final VoidCallback onResults;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 58,
            color: AppColors.success,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Result saved',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(studentName),
          Text(
            '${result.correct} / ${result.total}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: onNext,
            child: const Text('Grade next paper'),
          ),
          TextButton(
            onPressed: onResults,
            child: const Text('View class results'),
          ),
        ],
      ),
    ),
  );
}
