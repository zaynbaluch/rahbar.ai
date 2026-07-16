import 'package:flutter/material.dart';

import '../features/content/topic_picker_screen.dart';
import '../features/library/library_screen.dart';
import '../features/omr/results_overview_screen.dart';

/// The three existing teacher workflows: prepare, reopen, and review grading.
/// No destination advertises functionality that is not backed by current storage.
class RahbarShell extends StatefulWidget {
  const RahbarShell({super.key});

  @override
  State<RahbarShell> createState() => _RahbarShellState();
}

class _RahbarShellState extends State<RahbarShell> {
  int _index = 0;
  int _libraryRevision = 0;
  int _resultsRevision = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const TopicPickerScreen(),
      LibraryScreen(key: ValueKey(_libraryRevision)),
      ResultsOverviewScreen(key: ValueKey(_resultsRevision)),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
            if (value == 1) _libraryRevision++;
            if (value == 2) _resultsRevision++;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Results',
          ),
        ],
      ),
    );
  }
}
