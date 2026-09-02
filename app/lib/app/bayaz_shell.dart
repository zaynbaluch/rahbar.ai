import 'dart:async';

import 'package:flutter/material.dart';

import '../features/curriculum/curriculum_home_screen.dart';
import '../features/content/topic_picker_screen.dart';
import '../features/library/library_screen.dart';
import '../features/omr/results_overview_screen.dart';
import '../features/omr/grade_papers_screen.dart';
import '../features/resources/background_ai_download_controller.dart';

class BayazShell extends StatefulWidget {
  const BayazShell({
    super.key,
    this.backgroundAiController,
    this.autoStartAi = true,
  });

  final BackgroundAiDownloadController? backgroundAiController;
  final bool autoStartAi;

  @override
  State<BayazShell> createState() => _BayazShellState();
}

class _BayazShellState extends State<BayazShell> {
  int _index = 0;
  int _libraryRevision = 0;
  int _resultsRevision = 0;
  late final BackgroundAiDownloadController _backgroundAi;
  late final bool _ownsBackgroundAi;

  @override
  void initState() {
    super.initState();
    _ownsBackgroundAi = widget.backgroundAiController == null;
    _backgroundAi =
        widget.backgroundAiController ?? BackgroundAiDownloadController();
    if (widget.autoStartAi) unawaited(_backgroundAi.startIfNeeded());
  }

  @override
  void dispose() {
    if (_ownsBackgroundAi) _backgroundAi.dispose();
    super.dispose();
  }

  void _selectTab(int value) {
    setState(() {
      _index = value;
      if (value == 1) _libraryRevision++;
      if (value == 2) _resultsRevision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      CurriculumHomeScreen(
        backgroundAiController: _backgroundAi,
        onGradePapers: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const GradePapersScreen())),
        onContinueRecent: () => _selectTab(1),
      ),
      LibraryScreen(
        key: ValueKey(_libraryRevision),
        onPrepareLesson: () =>
            launchTeacherWorkflow(context, TopicPickerMode.lesson),
        onCreateTest: () =>
            launchTeacherWorkflow(context, TopicPickerMode.test),
      ),
      ResultsOverviewScreen(key: ValueKey(_resultsRevision)),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'My Work',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Class Results',
          ),
        ],
      ),
    );
  }
}
