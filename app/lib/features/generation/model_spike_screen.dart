import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart' show PreferredBackend;

import 'inference_service.dart';
import 'llama_cpp_service.dart';
import 'spike_models.dart';

/// Week-1 on-device generation spike (see docs/07-3week-plan.md).
///
/// Lets us pick an ungated `.task` model, download it, load it, send a prompt,
/// watch tokens stream, and read back latency / throughput. This is a
/// de-risking harness, not the product UI — the real generate → review flow
/// comes later.
class ModelSpikeScreen extends StatefulWidget {
  const ModelSpikeScreen({super.key});

  @override
  State<ModelSpikeScreen> createState() => _ModelSpikeScreenState();
}

enum _Phase { idle, downloading, loading, generating }

class _ModelSpikeScreenState extends State<ModelSpikeScreen> {
  final _service = InferenceService(); // flutter_gemma (.task / .litertlm)
  final _llama = LlamaCppService(); // llama.cpp (GGUF)
  final _promptController = TextEditingController(
    text:
        'Write 2 multiple-choice questions (with answers) about the parts of a '
        'plant cell, for a Grade 6 science class.',
  );

  SpikeModel _selected = kSpikeModels.first;
  PreferredBackend _backend = kSpikeModels.first.defaultBackend;
  _Phase _phase = _Phase.idle;
  int _downloadPercent = 0;
  String _output = '';
  String? _error;

  // Simple metrics for the spike.
  Duration _elapsed = Duration.zero;
  int _tokenChunks = 0;
  double get _tokPerSec => _elapsed.inMilliseconds == 0
      ? 0
      : _tokenChunks / (_elapsed.inMilliseconds / 1000);

  bool get _busy => _phase != _Phase.idle;

  @override
  void dispose() {
    _promptController.dispose();
    _service.unload();
    _llama.unload();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _output = '';
      _tokenChunks = 0;
      _elapsed = Duration.zero;
    });

    final isGguf = _selected.format == ModelFormat.gguf;
    try {
      // 1+2. Load. GGUF (llama.cpp) is pushed locally — no download; flutter_gemma
      // models may need a network/local install first.
      if (isGguf) {
        setState(() => _phase = _Phase.loading);
        await _llama.load(_selected.localFile!);
      } else {
        setState(() {
          _phase = _Phase.downloading;
          _downloadPercent = 0;
        });
        await _service.ensureInstalled(
          _selected,
          onProgress: (p) => setState(() => _downloadPercent = p),
        );
        setState(() => _phase = _Phase.loading);
        await _service.load(_selected, backend: _backend);
      }

      // 3. Generate, streaming tokens, timing throughput.
      setState(() => _phase = _Phase.generating);
      final sw = Stopwatch()..start();
      final stream = isGguf
          ? _llama.generate(_promptController.text)
          : _service.generate(_promptController.text);
      await for (final chunk in stream) {
        setState(() {
          _output += chunk;
          _tokenChunks++;
          _elapsed = sw.elapsed;
        });
      }
      sw.stop();
      setState(() => _elapsed = sw.elapsed);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rahbar AI · Generation Spike'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('On-device model', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              DropdownButtonFormField<SpikeModel>(
                initialValue: _selected,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  for (final m in kSpikeModels)
                    DropdownMenuItem(
                      value: m,
                      child: Text('${m.displayName}  ·  ${m.sizeLabel}'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (m) => setState(() {
                        _selected = m ?? _selected;
                        _backend = _selected.defaultBackend;
                      }),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  _selected.note,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Backend', style: theme.textTheme.labelLarge),
                  const SizedBox(width: 12),
                  SegmentedButton<PreferredBackend>(
                    segments: const [
                      ButtonSegment(
                          value: PreferredBackend.cpu, label: Text('CPU')),
                      ButtonSegment(
                          value: PreferredBackend.gpu, label: Text('GPU')),
                    ],
                    selected: {_backend},
                    onSelectionChanged: _busy
                        ? null
                        : (s) => setState(() => _backend = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _promptController,
                minLines: 3,
                maxLines: 6,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Prompt',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _run,
                icon: const Icon(Icons.auto_awesome),
                label: Text(_busy ? 'Working…' : 'Generate on-device'),
              ),
              const SizedBox(height: 16),
              _StatusCard(
                phase: _phase,
                downloadPercent: _downloadPercent,
                modelName: _selected.displayName,
                tokPerSec: _tokPerSec,
                tokenChunks: _tokenChunks,
                elapsed: _elapsed,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              ],
              if (_output.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Output', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(_output),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.phase,
    required this.downloadPercent,
    required this.modelName,
    required this.tokPerSec,
    required this.tokenChunks,
    required this.elapsed,
  });

  final _Phase phase;
  final int downloadPercent;
  final String modelName;
  final double tokPerSec;
  final int tokenChunks;
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String line;
    Widget? progress;
    switch (phase) {
      case _Phase.idle:
        line = tokenChunks > 0
            ? 'Done · $tokenChunks chunks · ${elapsed.inMilliseconds} ms · '
                '${tokPerSec.toStringAsFixed(1)} chunks/s'
            : 'Idle — pick a model and generate.';
      case _Phase.downloading:
        line = 'Downloading $modelName … $downloadPercent%';
        progress = LinearProgressIndicator(value: downloadPercent / 100);
      case _Phase.loading:
        line = 'Loading $modelName into memory (CPU)…';
        progress = const LinearProgressIndicator();
      case _Phase.generating:
        line = 'Generating · $tokenChunks chunks · '
            '${tokPerSec.toStringAsFixed(1)} chunks/s';
        progress = const LinearProgressIndicator();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(line, style: theme.textTheme.bodyMedium),
            if (progress != null) ...[
              const SizedBox(height: 10),
              progress,
            ],
          ],
        ),
      ),
    );
  }
}
