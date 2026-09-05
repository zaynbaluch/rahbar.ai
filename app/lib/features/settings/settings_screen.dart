import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../curriculum/curriculum_catalog.dart';
import '../onboarding/onboarding_store.dart';
import '../resources/background_ai_download_controller.dart';
import 'resource_management_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.onboardingStore,
    this.downloadController,
  });
  final OnboardingStore? onboardingStore;
  final BackgroundAiDownloadController? downloadController;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final OnboardingStore _onboarding =
      widget.onboardingStore ?? OnboardingStore();
  late Future<OnboardingState> _profile = _onboarding.read();

  void _reload() => setState(() {
    _profile = _onboarding.read();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      child: FutureBuilder<OnboardingState>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: OutlinedButton(
                onPressed: _reload,
                child: const Text('Try again'),
              ),
            );
          }
          final state = snapshot.data ?? const OnboardingState();
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SettingsSectionTitle('Profile'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.person_outline_rounded,
                      title: 'Teacher name',
                      value: state.teacherName.trim().isEmpty
                          ? 'Not set'
                          : state.teacherName,
                      onTap: () => _editText(
                        title: 'Teacher name',
                        value: state.teacherName,
                        onSave: (value) => _onboarding.save(
                          state.copyWith(teacherName: value),
                        ),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.school_outlined,
                      title: 'School',
                      value: state.schoolName.trim().isEmpty
                          ? 'Not set'
                          : state.schoolName,
                      onTap: () => _editText(
                        title: 'School',
                        value: state.schoolName,
                        onSave: (value) =>
                            _onboarding.save(state.copyWith(schoolName: value)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SettingsSectionTitle('Teaching'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.menu_book_outlined,
                      title: 'Classes & subjects',
                      value: _teachingSummary(state),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TeachingSettingsScreen(
                              store: _onboarding,
                              initial: state,
                            ),
                          ),
                        );
                        _reload();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SettingsSectionTitle('Offline features'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.offline_bolt_outlined,
                      title: 'Offline AI',
                      value: 'Manage offline downloads',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ResourceManagementScreen(
                            downloadController: widget.downloadController,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SettingsSectionTitle('Support'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.bug_report_outlined,
                      title: 'Report a problem',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportProblemScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SettingsSectionTitle('About'),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.info_outline_rounded,
                      title: 'About Bayaz AI',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AboutBayazScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Future<void> _editText({
    required String title,
    required String value,
    required Future<void> Function(String value) onSave,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextSettingScreen(
          title: title,
          initialValue: value,
          onSave: onSave,
        ),
      ),
    );
    _reload();
  }

  String _teachingSummary(OnboardingState state) {
    final classes = CurriculumCatalog.classes
        .where((item) => state.selectedClasses.contains(item.code))
        .toList(growable: false);
    if (classes.isEmpty) return 'Not set';
    if (classes.length == 1) {
      final codes =
          state.selectedSubjectsByClass[classes.first.code] ?? const [];
      final names = classes.first.subjects
          .where((subject) => codes.contains(subject.code))
          .map((subject) => subject.name)
          .join(', ');
      return names.isEmpty
          ? classes.first.name
          : '${classes.first.name} · $names';
    }
    return '${classes.length} classes';
  }
}

class TextSettingScreen extends StatefulWidget {
  const TextSettingScreen({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onSave,
  });
  final String title;
  final String initialValue;
  final Future<void> Function(String value) onSave;

  @override
  State<TextSettingScreen> createState() => _TextSettingScreenState();
}

class _TextSettingScreenState extends State<TextSettingScreen> {
  late final _controller = TextEditingController(text: widget.initialValue);
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.onSave(_controller.text.trim());
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(labelText: widget.title),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    ),
  );
}

class TeachingSettingsScreen extends StatefulWidget {
  const TeachingSettingsScreen({
    super.key,
    required this.store,
    required this.initial,
  });
  final OnboardingStore store;
  final OnboardingState initial;

  @override
  State<TeachingSettingsScreen> createState() => _TeachingSettingsScreenState();
}

class _TeachingSettingsScreenState extends State<TeachingSettingsScreen> {
  late final Set<String> _classes;
  late final Map<String, Set<String>> _subjects;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _classes = widget.initial.selectedClasses.toSet();
    _subjects = {
      for (final entry in widget.initial.selectedSubjectsByClass.entries)
        entry.key: entry.value.toSet(),
    };
    for (final classCode in _classes) {
      final item = CurriculumCatalog.classByCode(classCode);
      if (item == null || item.subjects.isEmpty) continue;
      final validCodes = item.subjects.map((subject) => subject.code).toSet();
      final selected = _subjects.putIfAbsent(classCode, () => <String>{});
      selected.removeWhere((code) => !validCodes.contains(code));
      if (selected.isEmpty) selected.add(item.subjects.first.code);
    }
  }

  bool get _canSave =>
      _classes.isNotEmpty &&
      _classes.every((code) => _subjects[code]?.isNotEmpty ?? false);

  void _setClassSelected(CurriculumClass item, bool selected) {
    setState(() {
      if (!selected) {
        _classes.remove(item.code);
        _subjects.remove(item.code);
        return;
      }

      _classes.add(item.code);
      final values = _subjects.putIfAbsent(item.code, () => <String>{});
      final validCodes = item.subjects.map((subject) => subject.code).toSet();
      values.removeWhere((code) => !validCodes.contains(code));
      if (values.isEmpty && item.subjects.isNotEmpty) {
        values.add(item.subjects.first.code);
      }
    });
  }

  void _setSubjectSelected(
    CurriculumClass item,
    CurriculumSubject subject,
    bool selected,
  ) {
    setState(() {
      final values = _subjects.putIfAbsent(item.code, () => <String>{});
      if (selected) {
        _classes.add(item.code);
        values.add(subject.code);
        return;
      }
      if (!values.contains(subject.code)) return;

      if (values.length == 1) {
        if (item.subjects.length == 1) {
          _classes.remove(item.code);
          _subjects.remove(item.code);
        }
        return;
      }
      values.remove(subject.code);
    });
  }

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    setState(() => _saving = true);
    final byClass = <String, List<String>>{
      for (final code in _classes)
        code: (_subjects[code] ?? <String>{}).toList(growable: false),
    };
    final flat = byClass.values.expand((values) => values).toSet().toList();
    await widget.store.save(
      widget.initial.copyWith(
        selectedClasses: _classes.toList(growable: false),
        selectedSubjects: flat,
        selectedSubjectsByClass: byClass,
      ),
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Classes & subjects')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          for (final item in CurriculumCatalog.classes) ...[
            CheckboxListTile(
              value: _classes.contains(item.code),
              title: Text(item.name),
              contentPadding: EdgeInsets.zero,
              onChanged: (selected) =>
                  _setClassSelected(item, selected == true),
            ),
            if (_classes.contains(item.code))
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.md),
                child: Column(
                  children: [
                    for (final subject in item.subjects)
                      CheckboxListTile(
                        value: (_subjects[item.code] ?? <String>{}).contains(
                          subject.code,
                        ),
                        title: Text(subject.name),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (selected) => _setSubjectSelected(
                          item,
                          subject,
                          selected == true,
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _saving || !_canSave ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    ),
  );
}

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});
  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final _details = TextEditingController();
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report not sent'),
        content: const Text(
          'No report destination is configured in this build. Bayaz has not uploaded your description or any device data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Report a problem')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const Text(
            'Describe what happened. Diagnostic information stays on this device unless a future build provides an explicit way to send it.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _details,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'What went wrong? (optional)',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: _send, child: const Text('Send report')),
        ],
      ),
    ),
  );
}

class AboutBayazScreen extends StatelessWidget {
  const AboutBayazScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About Bayaz AI')),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/ui/branding/bayaz_logo.png',
                width: 120,
                semanticLabel: 'Bayaz AI',
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Bayaz AI',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'An offline-first teaching assistant for preparing lessons, creating tests, grading papers, and understanding class results.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Version 1.0.0'),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => BayazCard(
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const Divider(height: 1),
        ],
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
  });
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: AppColors.primary),
    title: Text(title),
    subtitle: value == null ? null : Text(value!),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
