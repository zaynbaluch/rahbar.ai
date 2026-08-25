import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../resources/download_manager.dart';
import '../resources/resource_manager.dart';
import '../resources/resource_manifest.dart';

class ResourceManagementScreen extends StatefulWidget {
  const ResourceManagementScreen({super.key, this.manager});

  final ResourceManager? manager;

  @override
  State<ResourceManagementScreen> createState() =>
      _ResourceManagementScreenState();
}

class _ResourceManagementScreenState extends State<ResourceManagementScreen> {
  late final ResourceManager _manager = widget.manager ?? ResourceManager();
  List<ResourceDescriptor> _resources = const [];
  final Set<String> _installed = {};
  DownloadCancellationToken? _token;
  bool _loading = true;
  bool _downloading = false;
  double? _progress;
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
    _load();
  }

  @override
  void dispose() {
    _token?.cancel();
    _manager.dispose();
    super.dispose();
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
    if (_downloading) return;
    final missing = _resources
        .where((resource) => !_installed.contains(resource.id))
        .toList(growable: false);
    if (missing.isEmpty) return;
    final token = DownloadCancellationToken();
    setState(() {
      _token = token;
      _downloading = true;
      _progress = null;
      _error = null;
    });
    try {
      for (var index = 0; index < missing.length; index++) {
        final resource = missing[index];
        if (!resource.isDownloadable) {
          throw StateError('download unavailable');
        }
        await _manager.install(
          resource.id,
          cancellationToken: token,
          onProgress: (progress) {
            if (!mounted) return;
            final combined =
                (index + (progress.fraction ?? 0)) / missing.length.toDouble();
            setState(() => _progress = combined.clamp(0, 1));
          },
        );
        _installed.add(resource.id);
      }
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _token = null;
        _progress = 1;
      });
    } on DownloadCancelled {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _token = null;
        _progress = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _token = null;
        _progress = null;
        _error = 'The offline download needs attention.';
      });
    }
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
    if (!mounted) return;
    setState(() {
      _installed.clear();
      _error = null;
      _progress = null;
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
    final status = _downloading
        ? 'Downloading'
        : _error != null
        ? 'Needs attention'
        : _ready
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
                    backgroundColor: _ready
                        ? const Color(0xFFE7F6EC)
                        : AppColors.softBlue,
                    child: Icon(
                      _ready
                          ? Icons.check_rounded
                          : Icons.offline_bolt_outlined,
                      color: _ready ? AppColors.success : AppColors.primary,
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
                          _ready
                              ? 'Offline features are available on this device.'
                              : 'Offline AI supports custom lessons, custom tests, and Ask Bayaz.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!_ready && !_downloading && _totalBytes > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Download size: about ${_formatBytes(_totalBytes)}'),
              ],
              if (_downloading) ...[
                const SizedBox(height: AppSpacing.lg),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _progress == null
                      ? 'Starting download…'
                      : '${(_progress! * 100).round()}%',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (_downloading)
                OutlinedButton.icon(
                  onPressed: () => _token?.cancel(),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                )
              else if (!_ready)
                FilledButton.icon(
                  onPressed: _downloadAll,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    _error == null
                        ? 'Download Offline AI'
                        : 'Try download again',
                  ),
                ),
              if (_hasAny && !_downloading) ...[
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
