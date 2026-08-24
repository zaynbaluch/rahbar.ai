import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/section_header.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../content/topic_picker_screen.dart';
import '../settings/settings_screen.dart';
import 'curriculum_catalog.dart';

class CurriculumHomeScreen extends StatefulWidget {
  const CurriculumHomeScreen({super.key});

  @override
  State<CurriculumHomeScreen> createState() => _CurriculumHomeScreenState();
}

class _CurriculumHomeScreenState extends State<CurriculumHomeScreen> {


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
                    _ActionTile(icon: Icons.refresh_rounded, label: 'Continue Recent', onTap: () {}),
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


class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});
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
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
