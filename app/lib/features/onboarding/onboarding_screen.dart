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
    this.classes = CurriculumCatalog.classes,
  });

  final VoidCallback? onCompleted;
  final bool reconfigure;
  final OnboardingStore? store;
  final Future<LocalAiAvailability?> Function()? inspectAi;
  final List<CurriculumClass> classes;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _SetupPageKind { profile, classes, relationship, sharedSubjects, classSubjects }

class _SetupPage {
  const _SetupPage(this.kind, {this.classCode});
  final _SetupPageKind kind;
  final String? classCode;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
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
  bool? _sameSubjects;

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

  List<_SetupPage> get _pages {
    final selected = _selectedClasses;
    final pages = <_SetupPage>[
      const _SetupPage(_SetupPageKind.profile),
      const _SetupPage(_SetupPageKind.classes),
    ];
    if (selected.length <= 1) {
      if (selected.isNotEmpty) {
        pages.add(_SetupPage(_SetupPageKind.classSubjects, classCode: selected.first.code));
      }
      return pages;
    }
    pages.add(const _SetupPage(_SetupPageKind.relationship));
    if (_sameSubjects == true) {
      pages.add(const _SetupPage(_SetupPageKind.sharedSubjects));
    } else if (_sameSubjects == false) {
      pages.addAll(selected.map((c) => _SetupPage(_SetupPageKind.classSubjects, classCode: c.code)));
    }
    return pages;
  }

  List<CurriculumClass> get _selectedClasses => widget.classes
      .where((item) => _state.selectedClasses.contains(item.code))
      .toList(growable: false);

  int get _pageIndex => _state.currentStep.clamp(0, _pages.length - 1).toInt();
  _SetupPage get _page => _pages[_pageIndex];

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _loadError = null; });
    try {
      final stored = await _store.read();
      _teacherController.text = stored.teacherName;
      _schoolController.text = stored.schoolName;
      final selected = stored.selectedClasses.where((code) => widget.classes.any((c) => c.code == code)).toList();
      final fallbackClass = widget.classes.isEmpty ? <String>[] : <String>[widget.classes.first.code];
      final normalizedClasses = selected.isEmpty ? fallbackClass : selected;
      final mapping = <String, List<String>>{};
      for (final code in normalizedClasses) {
        final c = widget.classes.where((item) => item.code == code).firstOrNull;
        if (c == null) continue;
        final configured = stored.selectedSubjectsByClass[code] ?? stored.selectedSubjects;
        final valid = configured.where((subject) => c.subjects.any((s) => s.code == subject)).toList();
        mapping[code] = valid.isEmpty && c.subjects.isNotEmpty ? [c.subjects.first.code] : valid;
      }
      final values = mapping.values.map((v) => v.join('|')).toSet();
      _sameSubjects = normalizedClasses.length > 1 && values.length == 1 ? true : null;
      final normalized = stored.copyWith(
        currentStep: widget.reconfigure ? 0 : stored.currentStep,
        selectedClasses: normalizedClasses,
        selectedSubjectsByClass: mapping,
      );
      if (!mounted) return;
      setState(() { _state = normalized; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _loadError = 'Setup data could not be read.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.storage_rounded, size: 48),
              const SizedBox(height: AppSpacing.sm),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ]),
          ),
        ),
      );
    }
    return PopScope<void>(
      canPop: widget.reconfigure && _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.reconfigure) unawaited(_saveAndLeave());
      },
      child: Scaffold(
        appBar: widget.reconfigure ? AppBar(title: const Text('Teaching setup')) : null,
        body: SafeArea(
          child: Column(children: [
            LinearProgressIndicator(value: (_pageIndex + 1) / _pages.length, minHeight: 5),
            Expanded(child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(key: ValueKey('${_page.kind}-${_page.classCode}'), child: _buildPage()),
            )),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(_saveError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            _navigation(),
          ]),
        ),
      ),
    );
  }

  Widget _buildPage() => switch (_page.kind) {
    _SetupPageKind.profile => _profilePage(),
    _SetupPageKind.classes => _classesPage(),
    _SetupPageKind.relationship => _relationshipPage(),
    _SetupPageKind.sharedSubjects => _sharedSubjectsPage(),
    _SetupPageKind.classSubjects => _classSubjectsPage(_page.classCode!),
  };

  Widget _pageLayout(String title, List<Widget> children, {String? subtitle}) => ListView(
    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      if (subtitle != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      ],
      const SizedBox(height: AppSpacing.xl),
      ...children,
    ],
  );

  Widget _profilePage() => _pageLayout(
    widget.reconfigure ? 'Teacher profile' : 'Welcome to Bayaz',
    [
      if (!widget.reconfigure) ...[
        Center(child: SizedBox(width: 112, height: 112, child: Image.asset('assets/ui/branding/bayaz_logo.png', fit: BoxFit.contain))),
        const SizedBox(height: AppSpacing.xl),
      ],
      TextField(
        controller: _teacherController,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Teacher name', prefixIcon: Icon(Icons.person_outline_rounded)),
        onChanged: (_) => _scheduleDraftSave(),
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _schoolController,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'School name (optional)', prefixIcon: Icon(Icons.school_outlined)),
        onChanged: (_) => _scheduleDraftSave(),
      ),
    ],
  );

  Widget _classesPage() => _pageLayout(
    'Which classes do you teach?',
    [
      for (final item in widget.classes)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: BayazCard(
            onTap: () => _toggleClass(item.code),
            borderColor: _state.selectedClasses.contains(item.code) ? AppColors.primary : null,
            child: Row(children: [
              Checkbox(value: _state.selectedClasses.contains(item.code), onChanged: (_) => _toggleClass(item.code)),
              Expanded(child: Text(item.name, style: Theme.of(context).textTheme.titleMedium)),
            ]),
          ),
        ),
    ],
  );

  Widget _relationshipPage() => _pageLayout(
    'Do you teach the same subjects in these classes?',
    [
      _choiceCard('Yes, same subjects', _sameSubjects == true, () => setState(() => _sameSubjects = true)),
      const SizedBox(height: AppSpacing.md),
      _choiceCard('No, they are different', _sameSubjects == false, () => setState(() => _sameSubjects = false)),
    ],
  );

  Widget _choiceCard(String label, bool selected, VoidCallback onTap) => BayazCard(
    onTap: onTap,
    borderColor: selected ? AppColors.primary : null,
    child: Row(children: [
      Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? AppColors.primary : null),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
    ]),
  );

  List<CurriculumSubject> get _sharedAvailableSubjects {
    final selected = _selectedClasses;
    if (selected.isEmpty) return const [];
    return selected.first.subjects.where((subject) =>
      selected.every((c) => c.subjects.any((s) => s.code == subject.code))
    ).toList(growable: false);
  }

  Widget _sharedSubjectsPage() {
    final subjects = _sharedAvailableSubjects;
    final applied = _selectedClasses.map((c) => c.name).join(' · ');
    final selected = _state.selectedSubjectsByClass[_selectedClasses.first.code] ?? const <String>[];
    return _pageLayout('What subjects do you teach?', [
      Text('Applies to: $applied'),
      const SizedBox(height: AppSpacing.md),
      ...subjects.map((s) => CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: selected.contains(s.code),
        title: Text(s.name),
        onChanged: (_) => _toggleSharedSubject(s.code),
      )),
    ]);
  }

  Widget _classSubjectsPage(String classCode) {
    final c = widget.classes.firstWhere((item) => item.code == classCode);
    final selected = _state.selectedSubjectsByClass[classCode] ?? const <String>[];
    return _pageLayout('Subjects for ${c.name}', [
      for (final subject in c.subjects)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: selected.contains(subject.code),
          title: Text(subject.name),
          onChanged: (_) => _toggleSubject(classCode, subject.code),
        ),
    ]);
  }

  void _toggleClass(String code) {
    final next = List<String>.of(_state.selectedClasses);
    if (next.contains(code)) {
      if (next.length == 1) return;
      next.remove(code);
    } else {
      next.add(code);
    }
    final mapping = Map<String, List<String>>.fromEntries(_state.selectedSubjectsByClass.entries.map((e) => MapEntry(e.key, List<String>.of(e.value))));
    for (final classCode in next) {
      if (mapping[classCode]?.isNotEmpty == true) continue;
      final c = widget.classes.firstWhere((item) => item.code == classCode);
      if (c.subjects.isNotEmpty) mapping[classCode] = [c.subjects.first.code];
    }
    mapping.removeWhere((key, _) => !next.contains(key));
    setState(() {
      _sameSubjects = next.length > 1 ? null : _sameSubjects;
      _state = _state.copyWith(selectedClasses: next, selectedSubjectsByClass: mapping);
    });
    _scheduleDraftSave();
  }

  void _toggleSubject(String classCode, String subjectCode) {
    final mapping = _copyMapping();
    final selected = mapping[classCode] ?? <String>[];
    if (selected.contains(subjectCode)) {
      if (selected.length == 1) return;
      selected.remove(subjectCode);
    } else {
      selected.add(subjectCode);
    }
    mapping[classCode] = selected;
    setState(() => _state = _state.copyWith(selectedSubjectsByClass: mapping));
    _scheduleDraftSave();
  }

  void _toggleSharedSubject(String subjectCode) {
    final mapping = _copyMapping();
    final firstCode = _selectedClasses.first.code;
    final current = List<String>.of(mapping[firstCode] ?? const []);
    if (current.contains(subjectCode)) {
      if (current.length == 1) return;
      current.remove(subjectCode);
    } else {
      current.add(subjectCode);
    }
    for (final c in _selectedClasses) mapping[c.code] = List<String>.of(current);
    setState(() => _state = _state.copyWith(selectedSubjectsByClass: mapping));
    _scheduleDraftSave();
  }

  Map<String, List<String>> _copyMapping() => Map<String, List<String>>.fromEntries(
    _state.selectedSubjectsByClass.entries.map((e) => MapEntry(e.key, List<String>.of(e.value))),
  );

  bool get _pageValid => switch (_page.kind) {
    _SetupPageKind.profile => true,
    _SetupPageKind.classes => _selectedClasses.isNotEmpty,
    _SetupPageKind.relationship => _sameSubjects != null,
    _SetupPageKind.sharedSubjects => _selectedClasses.isNotEmpty && (_state.selectedSubjectsByClass[_selectedClasses.first.code]?.isNotEmpty ?? false),
    _SetupPageKind.classSubjects => _state.selectedSubjectsByClass[_page.classCode]?.isNotEmpty ?? false,
  };

  Widget _navigation() {
    final last = _pageIndex == _pages.length - 1;
    final nextClass = !last && _page.kind == _SetupPageKind.classSubjects
        ? widget.classes.where((c) => c.code == _pages[_pageIndex + 1].classCode).firstOrNull?.name
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      child: Row(children: [
        if (_pageIndex > 0)
          TextButton.icon(onPressed: _saving ? null : _back, icon: const Icon(Icons.arrow_back_rounded), label: const Text('Back'))
        else
          const Spacer(),
        if (_pageIndex > 0) const Spacer(),
        FilledButton.icon(
          onPressed: _saving || !_pageValid ? null : (last ? _finish : _next),
          icon: Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
          label: Text(_saving ? 'Saving...' : last ? 'Finish' : nextClass == null ? 'Continue' : 'Next: $nextClass'),
        ),
      ]),
    );
  }

  Future<void> _next() async => _saveAndShow(_snapshot(currentStep: _pageIndex + 1));
  Future<void> _back() async => _saveAndShow(_snapshot(currentStep: _pageIndex - 1));

  Future<void> _finish() async {
    final completed = _snapshot(currentStep: _pageIndex, completed: true).copyWith(offlineAiEnabled: true);
    setState(() { _saving = true; _saveError = null; });
    try {
      await _drafts.flush(completed);
      if (!mounted) return;
      setState(() { _state = completed; if (widget.reconfigure) _allowPop = true; });
      if (widget.reconfigure) {
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
    setState(() { _saving = true; _saveError = null; });
    try {
      await _drafts.flush(updated);
      if (!mounted) return;
      setState(() { _state = updated; _saving = false; _allowPop = true; });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) setState(() { _saving = false; _saveError = 'Setup changes could not be saved.'; });
    }
  }

  OnboardingState _snapshot({int? currentStep, bool? completed}) {
    final union = <String>{for (final values in _state.selectedSubjectsByClass.values) ...values}.toList(growable: false);
    return _state.copyWith(
      currentStep: currentStep,
      completed: completed,
      teacherName: _teacherController.text.trim(),
      schoolName: _schoolController.text.trim(),
      selectedSubjects: union,
    );
  }

  void _scheduleDraftSave() {
    final updated = _snapshot();
    _state = updated;
    _drafts.schedule(updated);
  }

  Future<void> _saveAndShow(OnboardingState updated) async {
    if (_saving) return;
    setState(() { _saving = true; _saveError = null; });
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
