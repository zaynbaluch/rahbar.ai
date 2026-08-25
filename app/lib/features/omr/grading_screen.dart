import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../design_system/components/frame_animation.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/status_chip.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../curriculum/teaching_context.dart';
import '../export/pdf_export.dart';
import '../generation/mcq_parser.dart';
import 'gradebook_store.dart';
import 'graded_result.dart';
import 'image_pick_recovery.dart';
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
  });

  final McqTest test;
  final String? initialImagePath;
  final PendingImagePickStore? recoveryStore;
  final ImagePicker? picker;
  final OmrImageProcessor? imageProcessor;
  final GradebookStore? gradebookStore;
  final TeachingContext? teachingContext;

  @override
  State<GradingScreen> createState() => _GradingScreenState();
}

class _GradingScreenState extends State<GradingScreen> {
  late final ImagePicker _picker;
  late final PendingImagePickStore _recoveryStore;
  late final OmrImageProcessor _imageProcessor;
  late final GradebookStore _gradebook;
  late final Future<void> _studentNamesReady;
  final Set<String> _studentNames = {};
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  OmrResult? _result;
  bool _saved = false;
  bool _saving = false;
  int _nextStudentNumber = 1;
  bool _reviewConfirmed = false;

  String get _testId => PdfExport.testId(widget.test);

  @override
  void initState() {
    super.initState();
    _picker = widget.picker ?? ImagePicker();
    _recoveryStore = widget.recoveryStore ?? PendingImagePickStore();
    _imageProcessor = widget.imageProcessor ?? OmrImageProcessor();
    _gradebook = widget.gradebookStore ?? GradebookStore();
    _studentNamesReady = _loadExistingStudentNames();
    final initialPath = widget.initialImagePath;
    if (initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _gradePath(initialPath, clearRecovery: true);
      });
    }
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
      _saved = false;
      _reviewConfirmed = false;
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
    } catch (error) {
      await _recoveryStore.clear();
      if (mounted) setState(() => _error = '$error');
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
        _saved = false;
        _reviewConfirmed = false;
      });
    }
    try {
      await _studentNamesReady;
      final bytes = await File(path).readAsBytes();
      final result = await _imageProcessor.process(bytes, widget.test);
      if (!result.fiducialsFound) {
        throw 'The four corner markers were not detected. Retake the image with only the ANSWERS box filling the frame, on a flat surface and without shadows.';
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _name.text = 'Student $_nextStudentNumber';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (clearRecovery) await _recoveryStore.clear();
      if (!alreadyBusy && mounted) setState(() => _busy = false);
    }
  }

  void _setMark(int questionNumber, String? mark) {
    final current = _result;
    if (current == null || _saved) return;
    setState(() {
      _result = current.withMark(questionNumber, mark);
    });
  }

  Future<void> _saveResult() async {
    final result = _result;
    if (result == null || _saved || _saving) return;
    if (result.needsReview > 0 && !_reviewConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Confirm that you reviewed the uncertain or blank answers.',
          ),
        ),
      );
      return;
    }
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
      if (!mounted) return;
      setState(() {
        _saved = true;
        _studentNames.add(studentName);
        _nextStudentNumber = StudentNameSequence.nextNumber(_studentNames);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Result saved')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save this result: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openResults() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ResultsScreen(testId: _testId, topic: widget.test.topic),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grade answer sheets'),
        actions: [
          IconButton(
            tooltip: 'Class results for this paper',
            onPressed: _openResults,
            icon: const Icon(Icons.people_alt_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            _GradingHeader(test: widget.test),
            const SizedBox(height: AppSpacing.md),
            _CaptureGuide(),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _grade(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(result == null ? 'Open camera' : 'Next paper'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _grade(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose image'),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: AppSpacing.md),
              BayazCard(
                child: Column(
                  children: [
                    const BayazFrameAnimation(
                      name: 'scanning_answers',
                      size: 150,
                      loop: true,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Reading the answer bubbles…',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const LinearProgressIndicator(),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              BayazCard(
                color: Theme.of(context).colorScheme.errorContainer,
                borderColor: Theme.of(context).colorScheme.error,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Could not grade this image',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(_error!),
                  ],
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _ResultSummary(result: result),
              const SizedBox(height: AppSpacing.sm),
              BayazCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      enabled: !_saved,
                      decoration: const InputDecoration(
                        labelText: 'Student name or roll number',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    if (result.needsReview > 0) ...[
                      const SizedBox(height: AppSpacing.sm),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _reviewConfirmed,
                        onChanged: _saved
                            ? null
                            : (value) => setState(
                                () => _reviewConfirmed = value ?? false,
                              ),
                        title: const Text(
                          'I reviewed the uncertain and blank answers',
                        ),
                        subtitle: Text(
                          '${result.needsReview} answers require teacher confirmation.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _saved || _saving ? null : _saveResult,
                      icon: Icon(
                        _saved
                            ? Icons.check_circle_rounded
                            : Icons.verified_outlined,
                      ),
                      label: Text(
                        _saved
                            ? 'Result saved'
                            : _saving
                            ? 'Saving…'
                            : 'Confirm and save result',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Question review',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              BayazCard(
                child: Column(
                  children: [
                    for (final question in result.questions)
                      _QuestionResultRow(
                        question: question,
                        enabled: !_saved,
                        onChanged: (mark) => _setMark(question.number, mark),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GradingHeader extends StatelessWidget {
  const _GradingHeader({required this.test});
  final McqTest test;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            test.topic,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Grade only papers printed from this exact test.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          StatusChip(
            label: 'Paper ID ${test.id}',
            icon: Icons.fingerprint,
            backgroundColor: Colors.white.withValues(alpha: 0.14),
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _CaptureGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BayazCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Capture the ANSWERS box',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Keep all four black markers visible. Use even lighting, hold the phone parallel to the paper, and avoid shadows.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/ui/grading/omr_capture_guide.webp',
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
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
    final percentage = result.total == 0
        ? 0
        : (100 * result.correct / result.total).round();
    return BayazCard(
      color: const Color(0xFFF3F8FF),
      borderColor: const Color(0xFFC9D6FF),
      child: Row(
        children: [
          const BayazFrameAnimation(name: 'grading_complete', size: 116),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.correct}/${result.total}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  '$percentage% score',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusChip(
                      label: '${result.correct} correct',
                      icon: Icons.check_circle_outline,
                      backgroundColor: const Color(0xFFDDF5E8),
                      foregroundColor: AppColors.success,
                    ),
                    StatusChip(
                      label:
                          '${result.total - result.correct - result.blank} incorrect',
                      icon: Icons.cancel_outlined,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    if (result.blank > 0)
                      StatusChip(
                        label: '${result.blank} blank',
                        icon: Icons.help_outline,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionResultRow extends StatelessWidget {
  const _QuestionResultRow({
    required this.question,
    required this.enabled,
    required this.onChanged,
  });
  final OmrQuestion question;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final blank = question.marked == null;
    final correct = question.isRight;
    final color = blank
        ? AppColors.textSecondary
        : correct
        ? AppColors.success
        : Theme.of(context).colorScheme.error;
    final icon = blank
        ? Icons.help_outline
        : correct
        ? Icons.check_circle_rounded
        : Icons.cancel_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Q${question.number}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          Text('Key ${question.correct ?? '?'}'),
          const SizedBox(width: AppSpacing.sm),
          DropdownButton<String?>(
            value: question.marked,
            onChanged: enabled ? onChanged : null,
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Blank')),
              DropdownMenuItem<String?>(value: 'A', child: Text('A')),
              DropdownMenuItem<String?>(value: 'B', child: Text('B')),
              DropdownMenuItem<String?>(value: 'C', child: Text('C')),
              DropdownMenuItem<String?>(value: 'D', child: Text('D')),
            ],
          ),
        ],
      ),
    );
  }
}
