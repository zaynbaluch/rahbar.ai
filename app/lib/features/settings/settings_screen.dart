import 'package:flutter/material.dart';

import '../../design_system/components/bayaz_card.dart';
import '../../design_system/components/section_header.dart';
import '../../design_system/theme/app_colors.dart';
import '../../design_system/theme/app_spacing.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/onboarding_store.dart';
import 'resource_management_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _onboarding = OnboardingStore();
  OnboardingState? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _onboarding.read();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Setup')),
      body: SafeArea(
        child: profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                children: [
                  const SectionHeader(
                    title: 'Teacher setup',
                    subtitle: 'Profile, coursework, and optional offline AI',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  BayazCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.softBlue,
                            child: Icon(
                              Icons.person_outline_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          title: Text(
                            profile.teacherName.trim().isEmpty
                                ? 'Teacher profile'
                                : profile.teacherName,
                          ),
                          subtitle: Text(
                            profile.schoolName.trim().isEmpty
                                ? 'School not specified'
                                : profile.schoolName,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _editOnboarding,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Review setup'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(
                    title: 'Downloads',
                    subtitle: 'Manage optional offline AI models',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  BayazCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ResourceManagementScreen(),
                    )),
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.download_for_offline_outlined,
                        color: AppColors.primary,
                      ),
                      title: Text('Manage offline resources'),
                      subtitle: Text(
                        'Class 6 coursework is included. AI models are optional.',
                      ),
                      trailing: Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(
                    title: 'Data on this device',
                    subtitle: 'The current MVP has no cloud analytics or background sync',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const BayazCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lessons, tests, grading results, generated content, and chat '
                          'remain on this device unless the teacher deliberately exports a file.',
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text(
                          'The app does not automatically upload teaching activity or run '
                          'background synchronization.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _editOnboarding() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const OnboardingScreen(reconfigure: true),
    ));
    await _load();
  }
}
