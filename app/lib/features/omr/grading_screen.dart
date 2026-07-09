import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../generation/mcq_parser.dart';
import 'omr_grader.dart';

/// Camera-based OMR grading: photograph a filled answer sheet, read the bubbles,
/// and score against this test's stored key — no SLM (see ADR-007). One tap per
/// student sheet; the key stays in memory so a stack can be graded quickly.
class GradingScreen extends StatefulWidget {
  const GradingScreen({super.key, required this.test});

  final McqTest test;

  @override
  State<GradingScreen> createState() => _GradingScreenState();
}

class _GradingScreenState extends State<GradingScreen> {
  final _picker = ImagePicker();
  bool _busy = false;
  String? _error;
  OmrResult? _result;

  Future<void> _capture() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600, // enough resolution for bubble detection, keeps it fast
      );
      if (shot == null) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await shot.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw 'Could not read the photo.';
      final result = OmrGrader.grade(decoded, widget.test);
      if (!result.fiducialsFound) {
        throw 'Could not find the 4 corner markers — retake with the whole sheet '
            'flat and well-lit.';
      }
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Grade Answer Sheets')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.test.topic, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Photograph a filled answer sheet — keep all four black corner '
                'markers in frame, flat and well-lit.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _capture,
                icon: const Icon(Icons.camera_alt),
                label: Text(_busy
                    ? 'Reading…'
                    : (r == null ? 'Capture sheet' : 'Grade next sheet')),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!,
                        style:
                            TextStyle(color: theme.colorScheme.onErrorContainer)),
                  ),
                ),
              ],
              if (r != null) ...[
                const SizedBox(height: 20),
                _ScoreCard(result: r),
                const SizedBox(height: 12),
                for (final q in r.questions) _QRow(q: q),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.result});
  final OmrResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = result.total == 0 ? 0 : (100 * result.correct / result.total).round();
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text('${result.correct}/${result.total}',
                style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '$pct%'
                '${result.blank > 0 ? '  ·  ${result.blank} blank' : ''}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QRow extends StatelessWidget {
  const _QRow({required this.q});
  final OmrQuestion q;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = q.marked == null
        ? theme.colorScheme.outline
        : (q.isRight ? Colors.green : theme.colorScheme.error);
    final icon = q.marked == null
        ? Icons.help_outline
        : (q.isRight ? Icons.check_circle : Icons.cancel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text('Q${q.number}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('marked ${q.marked ?? '—'}   ·   key ${q.correct ?? '?'}',
              style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
