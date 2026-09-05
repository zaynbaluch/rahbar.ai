import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/atomic_file_store.dart';

class OnboardingState {
  const OnboardingState({
    this.schemaVersion = 2,
    this.currentStep = 0,
    this.completed = false,
    this.teacherName = '',
    this.schoolName = '',
    this.selectedClasses = const ['6'],
    this.selectedSubjects = const ['general_science'],
    this.selectedSubjectsByClass = const {
      '6': ['general_science'],
    },
    this.offlineAiEnabled = false,
  });

  final int schemaVersion;
  final int currentStep;
  final bool completed;
  final String teacherName;
  final String schoolName;
  final List<String> selectedClasses;
  final List<String> selectedSubjects;
  final Map<String, List<String>> selectedSubjectsByClass;
  final bool offlineAiEnabled;

  OnboardingState copyWith({
    int? currentStep,
    bool? completed,
    String? teacherName,
    String? schoolName,
    List<String>? selectedClasses,
    List<String>? selectedSubjects,
    Map<String, List<String>>? selectedSubjectsByClass,
    bool? offlineAiEnabled,
  }) => OnboardingState(
    schemaVersion: schemaVersion,
    currentStep: currentStep ?? this.currentStep,
    completed: completed ?? this.completed,
    teacherName: teacherName ?? this.teacherName,
    schoolName: schoolName ?? this.schoolName,
    selectedClasses: selectedClasses ?? this.selectedClasses,
    selectedSubjects: selectedSubjects ?? this.selectedSubjects,
    selectedSubjectsByClass:
        selectedSubjectsByClass ?? this.selectedSubjectsByClass,
    offlineAiEnabled: offlineAiEnabled ?? this.offlineAiEnabled,
  );

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'current_step': currentStep,
    'completed': completed,
    'teacher_name': teacherName,
    'school_name': schoolName,
    'selected_classes': selectedClasses,
    'selected_subjects': selectedSubjects,
    'selected_subjects_by_class': selectedSubjectsByClass,
    'offline_ai_enabled': offlineAiEnabled,
  };

  factory OnboardingState.fromJson(Map<String, Object?> json) =>
      OnboardingState(
        schemaVersion: 2,
        currentStep: json['current_step'] as int? ?? 0,
        completed: json['completed'] as bool? ?? false,
        teacherName: json['teacher_name'] as String? ?? '',
        schoolName: json['school_name'] as String? ?? '',
        selectedClasses: (json['selected_classes'] as List? ?? const ['6'])
            .map((item) => item.toString())
            .toList(growable: false),
        selectedSubjects:
            (json['selected_subjects'] as List? ?? const ['general_science'])
                .map((item) => item.toString())
                .toList(growable: false),
        selectedSubjectsByClass: _subjectsByClassFromJson(json),
        offlineAiEnabled: (json['completed'] as bool?) == true
            ? true
            : (json['offline_ai_enabled'] as bool? ?? false),
      );
}

class OnboardingStore {
  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'preferences', 'onboarding.v1.json'));
  }

  Future<OnboardingState> read() async {
    final file = await _file();
    if (!await file.exists()) return const OnboardingState();
    try {
      return OnboardingState.fromJson(
        Map<String, Object?>.from(jsonDecode(await file.readAsString()) as Map),
      );
    } catch (_) {
      await AtomicFileStore.shared.quarantineCorrupt(file);
      return const OnboardingState();
    }
  }

  Future<void> save(OnboardingState state) async {
    final file = await _file();
    await AtomicFileStore.shared.writeJson(file, state.toJson());
  }

  Future<void> reset() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

Map<String, List<String>> _subjectsByClassFromJson(Map<String, Object?> json) {
  final raw = json['selected_subjects_by_class'] as Map?;
  if (raw != null && raw.isNotEmpty) {
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        (value as List? ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
      ),
    );
  }
  final classes = (json['selected_classes'] as List? ?? const ['6'])
      .map((e) => e.toString())
      .toList(growable: false);
  final subjects =
      (json['selected_subjects'] as List? ?? const ['general_science'])
          .map((e) => e.toString())
          .toList(growable: false);
  return {
    for (final classCode in classes) classCode: List<String>.of(subjects),
  };
}
