import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/section_header.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../content/topic_picker_screen.dart';
import '../onboarding/onboarding_store.dart';
import '../resources/background_ai_download_controller.dart';
import '../settings/settings_screen.dart';
import 'curriculum_catalog.dart';

class CurriculumHomeScreen extends StatefulWidget {
  const CurriculumHomeScreen({
    super.key,
    this.backgroundAiController,
    this.onboardingStore,
    this.onPrepareLesson,
    this.onCreateTest,
    this.onGradePapers,
    this.onContinueRecent,
    this.openSettings,
  });

  final BackgroundAiDownloadController? backgroundAiController;
  final OnboardingStore? onboardingStore;
  final VoidCallback? onPrepareLesson;
  final VoidCallback? onCreateTest;
  final VoidCallback? onGradePapers;
  final VoidCallback? onContinueRecent;
  final Future<void> Function(BuildContext context)? openSettings;

  @override
  State<CurriculumHomeScreen> createState() => _CurriculumHomeScreenState();
}

class _CurriculumHomeScreenState extends State<CurriculumHomeScreen> {
  late final OnboardingStore _onboardingStore;
  late Future<OnboardingState> _teacher;
  bool _downloadCardDismissed = false;

  @override
  void initState() {
    super.initState();
    _onboardingStore = widget.onboardingStore ?? OnboardingStore();
    _teacher = _onboardingStore.read();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Open Settings',
                  child: Tooltip(
                    message: 'Open Settings',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _openSettings,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: Image.asset(
                          'assets/ui/branding/bayaz_logo.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FutureBuilder<OnboardingState>(
                future: _teacher,
                builder: (context, snapshot) {
                  final name = snapshot.data?.teacherName.trim() ?? '';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'السلام علیکم' : 'السلام علیکم، $name',
                        textDirection: TextDirection.rtl,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'آج کیا تیار کرنا ہے؟',
                        textDirection: TextDirection.rtl,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 1.08,
                  children: [
                    _ActionTile(
                      icon: Icons.menu_book_outlined,
                      label: 'Prepare Lesson',
                      onTap:
                          widget.onPrepareLesson ??
                          () => _openClass(CurriculumCatalog.classes.first),
                    ),
                    _ActionTile(
                      icon: Icons.quiz_outlined,
                      label: 'Create Test',
                      onTap:
                          widget.onCreateTest ??
                          () => _openClass(CurriculumCatalog.classes.first),
                    ),
                    _ActionTile(
                      icon: Icons.camera_alt_outlined,
                      label: 'Grade Papers',
                      onTap: widget.onGradePapers ?? () {},
                    ),
                    _ActionTile(
                      icon: Icons.refresh_rounded,
                      label: 'Continue Recent',
                      onTap: widget.onContinueRecent ?? () {},
                    ),
                  ],
                ),
              ),
              if (widget.backgroundAiController != null)
                StreamBuilder<BackgroundAiDownloadState>(
                  stream: widget.backgroundAiController!.stream,
                  initialData: widget.backgroundAiController!.state,
                  builder: (context, snapshot) =>
                      _downloadStatus(snapshot.data!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _downloadStatus(BackgroundAiDownloadState state) {
    if (state.completed || (!state.running && !state.needsAttention)) {
      return const SizedBox.shrink();
    }
    if (state.needsAttention) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Card(
          elevation: 5,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Offline AI needs attention',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text('Bayaz could not finish setting up offline AI.'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    FilledButton.tonal(
                      onPressed: widget.backgroundAiController!.retry,
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: _openSettings,
                      child: const Text('Settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_downloadCardDismissed) return const SizedBox.shrink();
    final progress = state.progress;
    final percent = progress == null ? null : (progress * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Card(
        elevation: 5,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Preparing offline AI',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hide download progress',
                    onPressed: () =>
                        setState(() => _downloadCardDismissed = true),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: AppSpacing.xs),
              Text(
                percent == null
                    ? 'You can keep using Bayaz.'
                    : '$percent% · You can keep using Bayaz.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final override = widget.openSettings;
    if (override != null) {
      await override(context);
    } else {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    }
    if (!mounted) return;
    setState(() => _teacher = _onboardingStore.read());
  }

  Future<void> _openClass(CurriculumClass curriculumClass) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SubjectPickerScreen(curriculumClass: curriculumClass),
        ),
      );
}

class SubjectPickerScreen extends StatelessWidget {
  const SubjectPickerScreen({super.key, required this.curriculumClass});
  final CurriculumClass curriculumClass;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(curriculumClass.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const SectionHeader(title: 'Choose a subject'),
            const SizedBox(height: AppSpacing.sm),
            for (final subject in curriculumClass.subjects)
              BayazCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TopicPickerScreen(
                      classCode: curriculumClass.code,
                      subjectCode: subject.code,
                      className: curriculumClass.name,
                      subjectName: subject.name,
                    ),
                  ),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.softGold,
                    child: Icon(
                      Icons.science_outlined,
                      color: AppColors.warningText,
                    ),
                  ),
                  title: Text(subject.name),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: AppColors.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
