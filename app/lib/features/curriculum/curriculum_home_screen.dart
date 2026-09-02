import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/section_header.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../content/content_service.dart';
import '../content/topic_picker_screen.dart';
import '../content/topic_screen.dart';
import '../settings/settings_screen.dart';
import 'curriculum_catalog.dart';
import 'recent_access_store.dart';

class CurriculumHomeScreen extends StatefulWidget {
  const CurriculumHomeScreen({super.key});

  @override
  State<CurriculumHomeScreen> createState() => _CurriculumHomeScreenState();
}

class _CurriculumHomeScreenState extends State<CurriculumHomeScreen> {
  final _recent = RecentAccessStore();
  late Future<List<RecentCurriculumAccess>> _recentFuture;

  @override
  void initState() {
    super.initState();
    _recentFuture = _recent.list();
  }

  void _refresh() {
    setState(() {
      _recentFuture = _recent.list();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Open Settings',
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    icon: const Icon(Icons.auto_awesome_rounded),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('السلام علیکم', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text('آج کیا تیار کرنا ہے؟'),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  children: [
                    _ActionTile(icon: Icons.menu_book_outlined, label: 'Prepare Lesson', onTap: () => _openClass(CurriculumCatalog.classes.first)),
                    _ActionTile(icon: Icons.quiz_outlined, label: 'Create Test', onTap: () => _openClass(CurriculumCatalog.classes.first)),
                    _ActionTile(icon: Icons.camera_alt_outlined, label: 'Grade Papers', onTap: () {}),
                    _ActionTile(icon: Icons.refresh_rounded, label: 'Continue Recent', onTap: _refresh),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openClass(CurriculumClass curriculumClass) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SubjectPickerScreen(curriculumClass: curriculumClass),
    ));
    _refresh();
  }

  Future<void> _openRecent(RecentCurriculumAccess recent) async {
    final content = ContentService();
    try {
      await content.init();
      final topic = content.topicById(recent.topicId);
      if (!mounted || topic == null) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TopicScreen(content: content, topic: topic),
      ));
    } finally {
      content.dispose();
      if (mounted) _refresh();
    }
  }
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
            const SectionHeader(
              title: 'Choose a subject',
              subtitle: 'Only installed or available modules are shown',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final subject in curriculumClass.subjects)
              BayazCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TopicPickerScreen(
                    classCode: curriculumClass.code,
                    subjectCode: subject.code,
                    className: curriculumClass.name,
                    subjectName: subject.name,
                  ),
                )),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.softGold,
                    child: Icon(Icons.science_outlined, color: AppColors.warningText),
                  ),
                  title: Text(subject.name),
                  subtitle: Text(subject.description),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prepare your next class',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Open the installed Class 6 General Science module or continue a recent topic.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.88)),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.tonalIcon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Browse Class 6'),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Image.asset(
            'assets/ui/branding/bayaz_logo.png',
            width: 68,
            height: 68,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

class _RecentTopicCard extends StatelessWidget {
  const _RecentTopicCard({required this.item, required this.onTap});
  final RecentCurriculumAccess item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BayazCard(
      onTap: onTap,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.history_rounded, color: AppColors.primary),
        title: Text(item.topicTitle),
        subtitle: const Text('Class 6 · General Science'),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override Widget build(BuildContext context) => BayazCard(onTap: onTap, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 32), const SizedBox(height: 8), Text(label, textAlign: TextAlign.center)])));
}
