import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/empty_state.dart';
import '../../design_system/components/section_header.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../resources/download_manager.dart';
import '../resources/resource_manager.dart';
import '../resources/resource_manifest.dart';

class ResourceManagementScreen extends StatefulWidget {
  const ResourceManagementScreen({super.key, this.setupMode = false});

  final bool setupMode;

  @override
  State<ResourceManagementScreen> createState() =>
      _ResourceManagementScreenState();
}

class _ResourceManagementScreenState extends State<ResourceManagementScreen> {
  final _manager = ResourceManager();
  final Map<String, bool> _installed = {};
  final Map<String, DownloadProgress> _progress = {};
  final Map<String, DownloadCancellationToken> _tokens = {};
  final Map<String, String> _errors = {};

  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final token in _tokens.values) {
      token.cancel();
    }
    _manager.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _manager.init();
      final installed = <String, bool>{};
      for (final resource in _manager.resources()) {
        installed[resource.id] = await _manager.isInstalled(resource.id);
      }
      if (!mounted) return;
      setState(() {
        _installed
          ..clear()
          ..addAll(installed);
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.setupMode ? 'Set up offline AI' : 'Offline downloads'),
        actions: widget.setupMode
            ? [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ]
            : null,
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Could not read the download list',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _load();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final curriculum = _manager.resources(kind: ResourceKind.curriculumModule);
    final models = _manager
        .resources()
        .where((resource) => resource.kind != ResourceKind.curriculumModule)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        if (widget.setupMode) ...[
          const BayazCard(
            color: AppColors.softGold,
            child: Text(
              'Offline AI is optional. Verified lessons and tests work without these models. '
              'Model downloads can be completed later from Settings.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        const SectionHeader(
          title: 'Installed coursework',
          subtitle: 'The MVP ships with only the coursework it currently supports',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (curriculum.isEmpty)
          const BayazEmptyState(
            asset: 'assets/ui/illustrations/empty_library.webp',
            title: 'No coursework modules listed',
            message: 'Check the bundled runtime manifest.',
          )
        else
          for (final resource in curriculum) ...[
            _ResourceCard(
              resource: resource,
              installed: _installed[resource.id] ?? resource.isBundled,
              progress: _progress[resource.id],
              error: _errors[resource.id],
              onInstall: () => _install(resource),
              onCancel: () => _tokens[resource.id]?.cancel(),
              onRemove: () => _remove(resource),
              onVerify: () => _verify(resource),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(
          title: 'Optional offline AI',
          subtitle: 'Download only the models needed for custom generation and chat',
        ),
        const SizedBox(height: AppSpacing.sm),
        if (models.isEmpty)
          const BayazEmptyState(
            asset: 'assets/ui/illustrations/empty_library.webp',
            title: 'No models listed',
            message: 'Add approved model entries to the bundled runtime manifest.',
          )
        else
          for (final resource in models) ...[
            _ResourceCard(
              resource: resource,
              installed: _installed[resource.id] ?? false,
              progress: _progress[resource.id],
              error: _errors[resource.id],
              onInstall: () => _install(resource),
              onCancel: () => _tokens[resource.id]?.cancel(),
              onRemove: () => _remove(resource),
              onVerify: () => _verify(resource),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        const SizedBox(height: AppSpacing.md),
        const BayazCard(
          child: Text(
            'Provider URLs and exact SHA-256 checksums must be added to '
            'assets/config/runtime_manifest.json before a model can be downloaded. '
            'Bayaz does not host model files in this app repository.',
          ),
        ),
      ],
    );
  }

  Future<void> _install(ResourceDescriptor resource) async {
    if (!resource.isDownloadable) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Provider setup is incomplete'),
          content: Text(
            '${resource.displayName} is listed as an approved option, but this build '
            'does not yet include its provider URL, exact file size, and SHA-256 checksum.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    final token = DownloadCancellationToken();
    setState(() {
      _tokens[resource.id] = token;
      _progress.remove(resource.id);
      _errors.remove(resource.id);
    });
    try {
      await _manager.install(
        resource.id,
        cancellationToken: token,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress[resource.id] = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _installed[resource.id] = true;
        _tokens.remove(resource.id);
        _progress.remove(resource.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${resource.displayName} is ready.')),
      );
    } on DownloadCancelled {
      if (!mounted) return;
      setState(() {
        _tokens.remove(resource.id);
        _progress.remove(resource.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _tokens.remove(resource.id);
        _progress.remove(resource.id);
        _errors[resource.id] = '$error';
      });
    }
  }

  Future<void> _verify(ResourceDescriptor resource) async {
    final valid = await _manager.verify(resource.id);
    if (!mounted) return;
    setState(() => _installed[resource.id] = valid);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          valid
              ? '${resource.displayName} passed the checksum check.'
              : '${resource.displayName} is missing or corrupted. Remove it and retry.',
        ),
      ),
    );
  }

  Future<void> _remove(ResourceDescriptor resource) async {
    if (resource.required || resource.isBundled) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text(
          '${resource.displayName} will no longer be available offline. '
          'It can be downloaded again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _manager.remove(resource.id);
    if (!mounted) return;
    setState(() {
      _installed[resource.id] = false;
      _errors.remove(resource.id);
    });
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.resource,
    required this.installed,
    required this.onInstall,
    required this.onCancel,
    required this.onRemove,
    required this.onVerify,
    this.progress,
    this.error,
  });

  final ResourceDescriptor resource;
  final bool installed;
  final DownloadProgress? progress;
  final String? error;
  final VoidCallback onInstall;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final downloading = progress != null;
    final size = resource.sizeBytes <= 0
        ? 'Size not configured'
        : _formatBytes(resource.sizeBytes);
    final type = switch (resource.kind) {
      ResourceKind.curriculumModule => 'Coursework module',
      ResourceKind.embeddingModel => 'Curriculum search model',
      ResourceKind.languageModel => 'Content generation model',
    };

    return BayazCard(
      borderColor: error == null ? null : Theme.of(context).colorScheme.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor:
                    installed ? const Color(0xFFE7F6EC) : AppColors.softBlue,
                child: Icon(
                  installed ? Icons.check_rounded : _icon(resource.kind),
                  color: installed ? AppColors.success : AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('$type - $size'),
                    if (resource.licenseName.isNotEmpty)
                      Text(
                        resource.licenseName,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(value: progress!.fraction),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_formatBytes(progress!.receivedBytes)} of '
              '${_formatBytes(progress!.totalBytes)}',
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: downloading
                ? OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel'),
                  )
                : installed
                    ? resource.required || resource.isBundled
                        ? const Chip(label: Text('Included'))
                        : Wrap(
                            spacing: AppSpacing.sm,
                            children: [
                              OutlinedButton.icon(
                                onPressed: onVerify,
                                icon: const Icon(Icons.verified_outlined),
                                label: const Text('Verify'),
                              ),
                              OutlinedButton.icon(
                                onPressed: onRemove,
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('Remove'),
                              ),
                            ],
                          )
                    : FilledButton.icon(
                        onPressed: onInstall,
                        icon: Icon(
                          resource.isDownloadable
                              ? Icons.download_rounded
                              : Icons.info_outline_rounded,
                        ),
                        label: Text(
                          error != null
                              ? 'Retry download'
                              : resource.isDownloadable
                                  ? 'Download'
                                  : 'Provider not configured',
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  static IconData _icon(ResourceKind kind) => switch (kind) {
        ResourceKind.curriculumModule => Icons.menu_book_outlined,
        ResourceKind.embeddingModel => Icons.manage_search_rounded,
        ResourceKind.languageModel => Icons.auto_awesome_outlined,
      };

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}
