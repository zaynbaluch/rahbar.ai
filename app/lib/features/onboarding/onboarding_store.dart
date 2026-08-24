import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OnboardingState {
  const OnboardingState({
    this.schemaVersion = 2,
    this.currentStep = 0,
    this.completed = false,
    this.teacherName = '',
    this.schoolName = '',
    this.selectedClasses = const ['6'],
    this.selectedSubjects = const ['general_science'],
    this.offlineAiEnabled = false,
  });

  final int schemaVersion;
  final int currentStep;
  final bool completed;
  final String teacherName;
  final String schoolName;
  final List<String> selectedClasses;
  final List<String> selectedSubjects;
  final bool offlineAiEnabled;

  OnboardingState copyWith({
    int? currentStep,
    bool? completed,
    String? teacherName,
    String? schoolName,
    List<String>? selectedClasses,
    List<String>? selectedSubjects,
    bool? offlineAiEnabled,
  }) =>
      OnboardingState(
        schemaVersion: schemaVersion,
        currentStep: currentStep ?? this.currentStep,
        completed: completed ?? this.completed,
        teacherName: teacherName ?? this.teacherName,
        schoolName: schoolName ?? this.schoolName,
        selectedClasses: selectedClasses ?? this.selectedClasses,
        selectedSubjects: selectedSubjects ?? this.selectedSubjects,
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
        'offline_ai_enabled': offlineAiEnabled,
      };

  factory OnboardingState.fromJson(Map<String, Object?> json) => OnboardingState(
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
        offlineAiEnabled: json['offline_ai_enabled'] as bool? ?? false,
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
      final corrupt = File(
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}',
      );
      await file.rename(corrupt.path);
      return const OnboardingState();
    }
  }

  Future<void> save(OnboardingState state) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(state.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<void> reset() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
