import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/storage/debounced_writer.dart';
import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../curriculum/curriculum_catalog.dart';
import '../resources/local_ai_resources.dart';
import 'onboarding_store.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    this.onCompleted,
    this.reconfigure = false,
    this.store,
    this.inspectAi,
  });

  final VoidCallback? onCompleted;
  final bool reconfigure;
  final OnboardingStore? store;

  /// Overrides the on-device model probe. Tests inject this because the real
  /// probe reaches platform channels that never answer under widget tests.
  final Future<LocalAiAvailability?> Function()? inspectAi;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _stepCount = 2;

  late final OnboardingStore _store;
  final _teacherController = TextEditingController();
  final _schoolController = TextEditingController();
  late final DebouncedWriter<OnboardingState> _drafts;

  OnboardingState _state = const OnboardingState();
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _saveError;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? OnboardingStore();
    _drafts = DebouncedWriter<OnboardingState>(save: _store.save);
    _load();
  }

  @override
  void dispose() {
    _drafts.dispose();
    _teacherController.dispose();
    _schoolController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final stored = await _store.read();
      final step = widget.reconfigure
          ? 0
          : stored.currentStep.clamp(0, _stepCount - 1).toInt();
      final state = stored.copyWith(currentStep: step);
      _teacherController.text = state.teacherName;
      _schoolController.text = state.schoolName;
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Setup data could not be read.';
      });
    }
  }

  Future<void> _resetAndLoad() async {
    try {
      await _store.reset();
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Setup data could not be reset.');
      return;
    }
    await _load();
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_rounded, size: 48),
                const SizedBox(height: AppSpacing.sm),
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    FilledButton(
                      onPressed: _resetAndLoad,
                      child: const Text('Reset setup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return PopScope<void>(
      canPop: widget.reconfigure && _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.reconfigure) {
          unawaited(_saveAndLeave());
        }
      },
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
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text(
                    _saveError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        _ => _courseworkStep(),
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
            onChanged: (_) => _scheduleDraftSave(),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _schoolController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'School name (optional)',
              prefixIcon: Icon(Icons.school_outlined),
            ),
            onChanged: (_) => _scheduleDraftSave(),
          ),
        ],
      );

  Widget _courseworkStep() => _page(
        title: 'Which classes and subjects do you teach?',
        subtitle:
            'Choose the classes and subjects you teach so Bayaz can prepare lessons and tests for you.',
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
            'Only available classes and subjects are shown.',
          ),
        ],
      );

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
    await _saveAndShow(_snapshot(currentStep: next));
  }

  Future<void> _back() async {
    final previous = (_state.currentStep - 1).clamp(0, _stepCount - 1).toInt();
    await _saveAndShow(_snapshot(currentStep: previous));
  }


  Future<void> _finish() async {
    final completed = _snapshot(
      currentStep: _stepCount - 1,
      completed: true,
    );
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _drafts.flush(completed);
      if (!mounted) return;
      setState(() {
        _state = completed;
        if (widget.reconfigure) _allowPop = true;
      });
      if (widget.reconfigure) {
        // `pop` does not consult `canPop`, so this path was not stuck the way
        // `_saveAndLeave` was. Waiting for the frame that publishes the new pop
        // state still beats an arbitrary zero delay, and keeps both exits alike.
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.of(context).pop();
      } else {
        widget.onCompleted?.call();
      }
    } catch (_) {
      if (mounted) setState(() => _saveError = 'Setup changes could not be saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndLeave() async {
    if (!widget.reconfigure || _saving || _allowPop) return;
    final updated = _snapshot();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _drafts.flush(updated);
      if (!mounted) return;
      setState(() {
        _state = updated;
        _saving = false;
        _allowPop = true;
      });
      // The pop must wait for the frame that republishes `canPop: true`,
      // otherwise `PopScope` intercepts it again and the route never closes.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Setup changes could not be saved.';
        });
      }
    }
  }

  OnboardingState _snapshot({int? currentStep, bool? completed}) =>
      _state.copyWith(
        currentStep: currentStep,
        completed: completed,
        teacherName: _teacherController.text.trim(),
        schoolName: _schoolController.text.trim(),
      );

  void _scheduleDraftSave() {
    final updated = _snapshot();
    _state = updated;
    _drafts.schedule(updated);
  }

  Future<void> _saveAndShow(OnboardingState updated) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _drafts.flush(updated);
      if (mounted) setState(() => _state = updated);
    } catch (_) {
      if (mounted) setState(() => _saveError = 'Setup changes could not be saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

}
