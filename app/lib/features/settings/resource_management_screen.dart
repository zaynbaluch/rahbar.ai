import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../resources/background_ai_download_controller.dart';
import '../resources/resource_manager.dart';
import '../resources/resource_manifest.dart';

class ResourceManagementScreen extends StatefulWidget {
  const ResourceManagementScreen({
    super.key,
    this.manager,
    this.downloadController,
  });

  final ResourceManager? manager;
  final BackgroundAiDownloadController? downloadController;

  @override
  State<ResourceManagementScreen> createState() =>
      _ResourceManagementScreenState();
}

class _ResourceManagementScreenState extends State<ResourceManagementScreen> {
  late final ResourceManager _manager = widget.manager ?? ResourceManager();
  late final BackgroundAiDownloadController _downloads =
      widget.downloadController ?? BackgroundAiDownloadController.shared;
  StreamSubscription<BackgroundAiDownloadState>? _downloadSubscription;
  List<ResourceDescriptor> _resources = const [];
  final Set<String> _installed = {};
  bool _loading = true;
  bool _downloadWasRunning = false;
  String? _error;

  bool get _ready =>
      _resources.isNotEmpty &&
      _resources.every((r) => _installed.contains(r.id));
  bool get _hasAny => _installed.isNotEmpty;
  int get _totalBytes =>
      _resources.fold<int>(0, (total, resource) => total + resource.sizeBytes);

  @override
  void initState() {
    super.initState();
    _downloadWasRunning = _downloads.state.running;
    _downloadSubscription = _downloads.stream.listen(_onDownloadState);
    _load();
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _manager.dispose();
    super.dispose();
  }

  void _onDownloadState(BackgroundAiDownloadState state) {
    if (!mounted) return;
    final terminalAfterDownload = _downloadWasRunning && !state.running;
    _downloadWasRunning = state.running;
    setState(() {});
    if (terminalAfterDownload || state.completed) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      await _manager.init();
      final resources = _manager
          .resources()
          .where((resource) => resource.kind != ResourceKind.curriculumModule)
          .toList(growable: false);
      final installed = <String>{};
      for (final resource in resources) {
        if (await _manager.isInstalled(resource.id)) installed.add(resource.id);
      }
      if (!mounted) return;
      setState(() {
        _resources = resources;
        _installed
          ..clear()
          ..addAll(installed);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Bayaz couldn’t check the offline downloads.';
      });
    }
  }

  Future<void> _downloadAll() async {
    await _downloads.downloadMissing();
    if (mounted) await _load();
  }

  Future<void> _removeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Offline AI downloads?'),
        content: const Text(
          'Custom lessons, custom tests, and Ask Bayaz will be unavailable until the downloads are added again. Your saved work and results will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final resource in _resources) {
      if (_installed.contains(resource.id)) {
        await _manager.remove(resource.id);
      }
    }
    await _downloads.markDownloadsRemovedByUser();
    if (!mounted) return;
    setState(() {
      _installed.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Offline AI')),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _body(context),
    ),
  );

  Widget _body(BuildContext context) {
    final downloadState = _downloads.state;
    final downloading = downloadState.running;
    final ready = _ready || downloadState.completed;
    final controllerError = downloadState.needsAttention
        ? 'The offline download needs attention.'
        : null;
    final visibleError = _error ?? controllerError;
    final status = downloading
        ? 'Downloading'
        : visibleError != null
        ? 'Needs attention'
        : ready
        ? 'Ready'
        : 'Needs download';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        BayazCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: ready
                        ? const Color(0xFFE7F6EC)
                        : AppColors.softBlue,
                    child: Icon(
                      ready ? Icons.check_rounded : Icons.offline_bolt_outlined,
                      color: ready ? AppColors.success : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          ready
                              ? 'Offline features are available on this device.'
                              : 'Offline AI supports custom lessons, custom tests, and Ask Bayaz.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!ready && !downloading && _totalBytes > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Download size: about ${_formatBytes(_totalBytes)}'),
              ],
              if (downloading) ...[
                const SizedBox(height: AppSpacing.lg),
                LinearProgressIndicator(value: downloadState.progress),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  downloadState.progress == null
                      ? 'Starting download…'
                      : '${(downloadState.progress! * 100).round()}%',
                ),
              ],
              if (visibleError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  visibleError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (downloading)
                OutlinedButton.icon(
                  onPressed: _downloads.cancel,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                )
              else if (!ready)
                FilledButton.icon(
                  onPressed: _downloadAll,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    visibleError == null
                        ? 'Download Offline AI'
                        : 'Try download again',
                  ),
                ),
              if (_hasAny && !downloading) ...[
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: _removeAll,
                  child: const Text('Remove downloads'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const BayazCard(
          child: Text(
            'These downloads stay on this device. Removing them does not delete your saved lessons, tests, or class results.',
          ),
        ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).round()} MB';
  }
}
