import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../curriculum/curriculum_catalog.dart';
import '../resources/local_ai_resources.dart';
import '../settings/resource_management_screen.dart';
import 'onboarding_store.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    this.onCompleted,
    this.reconfigure = false,
  });

  final VoidCallback? onCompleted;
  final bool reconfigure;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepCount = 3;

  final _store = OnboardingStore();
  final _teacherController = TextEditingController();
  final _schoolController = TextEditingController();

  OnboardingState _state = const OnboardingState();
  LocalAiAvailability? _aiAvailability;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _teacherController.dispose();
    _schoolController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final stored = await _store.read();
    final step = widget.reconfigure
        ? 0
        : stored.currentStep.clamp(0, _stepCount - 1).toInt();
    final state = stored.copyWith(currentStep: step);
    _teacherController.text = state.teacherName;
    _schoolController.text = state.schoolName;
    final availability = await _inspectAi();
    if (!mounted) return;
    setState(() {
      _state = state;
      _aiAvailability = availability;
      _loading = false;
    });
  }

  Future<LocalAiAvailability?> _inspectAi() async {
    final resources = LocalAiResources();
    try {
      return await resources.inspect();
    } catch (_) {
      return null;
    } finally {
      resources.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: widget.reconfigure,
      child: Scaffold(
        appBar: widget.reconfigure
            ? AppBar(title: const Text('Review setup'))
            : null,
        body: SafeArea(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (_state.currentStep + 1) / _stepCount,
                minHeight: 5,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(
                    key: ValueKey(_state.currentStep),
                    child: _step(),
                  ),
                ),
              ),
              _navigation(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step() => switch (_state.currentStep) {
        0 => _profileStep(),
        1 => _courseworkStep(),
        _ => _offlineAiStep(),
      };

  Widget _page({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xl),
          ...children,
        ],
      );

  Widget _profileStep() => _page(
        title: widget.reconfigure ? 'Teacher profile' : 'Welcome to Bayaz AI',
        subtitle:
            'Set up the teacher app in three short steps. Profile details stay on this device.',
        children: [
          Center(
            child: Container(
              width: 132,
              height: 132,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/ui/branding/bayaz_logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _teacherController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Teacher name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            onChanged: (_) => _saveDraft(),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _schoolController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'School name (optional)',
              prefixIcon: Icon(Icons.school_outlined),
            ),
            onChanged: (_) => _saveDraft(),
          ),
        ],
      );

  Widget _courseworkStep() => _page(
        title: 'Installed coursework',
        subtitle:
            'The current MVP includes Class 6 General Science. More modules can be added later without making this setup longer.',
        children: [
          for (final curriculumClass in CurriculumCatalog.classes)
            BayazCard(
              borderColor: AppColors.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.softBlue,
                      child: Icon(Icons.school_outlined, color: AppColors.primary),
                    ),
                    title: Text(curriculumClass.name),
                    trailing: const Chip(label: Text('Installed')),
                  ),
                  for (final subject in curriculumClass.subjects)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.science_outlined,
                        color: AppColors.primary,
                      ),
                      title: Text(subject.name),
                      subtitle: Text(subject.description),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Only working modules are shown. There are no placeholder classes or subjects in the app.',
          ),
        ],
      );

  Widget _offlineAiStep() {
    final availability = _aiAvailability;
    final languageInstalled = availability?.languageModel.installed ?? false;
    final embeddingInstalled = availability?.embeddingModel.installed ?? false;
    final ready = languageInstalled && embeddingInstalled;
    return _page(
      title: 'Optional offline AI',
      subtitle:
          'Offline AI enables custom generation and clarification chat. It is not required for verified coursework.',
      children: [
        BayazCard(
          borderColor: _state.offlineAiEnabled ? AppColors.primary : null,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _state.offlineAiEnabled,
            onChanged: (value) {
              setState(() => _state = _state.copyWith(offlineAiEnabled: value));
              _saveDraft();
            },
            title: const Text('Enable offline AI features'),
            subtitle: const Text(
              'Model files can be large and generation may take several minutes on budget phones.',
            ),
          ),
        ),
        if (_state.offlineAiEnabled) ...[
          const SizedBox(height: AppSpacing.md),
          BayazCard(
            color: ready ? const Color(0xFFE7F6EC) : AppColors.softGold,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ready ? 'Offline AI is ready' : 'Model setup is incomplete',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Language model: ${languageInstalled ? 'installed' : 'not installed'}',
                ),
                Text(
                  'Curriculum search model: ${embeddingInstalled ? 'installed' : 'not installed'}',
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  !languageInstalled
                      ? 'Custom generation and chat remain unavailable until a language model is installed.'
                      : !embeddingInstalled
                          ? 'Generation can run, but it will be marked ungrounded.'
                          : 'Custom generation can use installed curriculum context.',
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _manageModels,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Manage models'),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        const Text(
          'You can skip this step and enable offline AI later from Settings.',
        ),
      ],
    );
  }

  Widget _navigation() {
    final last = _state.currentStep == _stepCount - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          if (_state.currentStep > 0)
            TextButton.icon(
              onPressed: _saving ? null : _back,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back'),
            )
          else
            const Spacer(),
          if (_state.currentStep > 0) const Spacer(),
          if (last && _state.offlineAiEnabled)
            TextButton(
              onPressed: _saving ? null : _skipOfflineAi,
              child: const Text('Skip for now'),
            ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            onPressed: _saving ? null : (last ? _finish : _next),
            icon: Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
            label: Text(_saving ? 'Saving...' : last ? 'Finish' : 'Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _next() async {
    final next = (_state.currentStep + 1).clamp(0, _stepCount - 1).toInt();
    final updated = _state.copyWith(
      currentStep: next,
      teacherName: _teacherController.text.trim(),
      schoolName: _schoolController.text.trim(),
    );
    await _store.save(updated);
    if (!mounted) return;
    setState(() => _state = updated);
  }

  Future<void> _back() async {
    final previous = (_state.currentStep - 1).clamp(0, _stepCount - 1).toInt();
    final updated = _state.copyWith(currentStep: previous);
    await _store.save(updated);
    if (!mounted) return;
    setState(() => _state = updated);
  }

  Future<void> _skipOfflineAi() async {
    setState(() => _state = _state.copyWith(offlineAiEnabled: false));
    await _finish();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final completed = _state.copyWith(
      currentStep: _stepCount - 1,
      completed: true,
      teacherName: _teacherController.text.trim(),
      schoolName: _schoolController.text.trim(),
    );
    await _store.save(completed);
    if (!mounted) return;
    setState(() {
      _state = completed;
      _saving = false;
    });
    if (widget.reconfigure) {
      Navigator.of(context).pop();
    } else {
      widget.onCompleted?.call();
    }
  }

  Future<void> _saveDraft() async {
    final updated = _state.copyWith(
      teacherName: _teacherController.text.trim(),
      schoolName: _schoolController.text.trim(),
    );
    _state = updated;
    await _store.save(updated);
  }

  Future<void> _manageModels() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ResourceManagementScreen(setupMode: true),
    ));
    final availability = await _inspectAi();
    if (!mounted) return;
    setState(() => _aiAvailability = availability);
  }
}
