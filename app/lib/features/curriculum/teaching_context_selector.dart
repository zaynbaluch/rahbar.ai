import 'package:flutter/material.dart';

import '../../design_system/theme/app_spacing.dart';
import 'curriculum_catalog.dart';
import 'teaching_context.dart';

Future<TeachingContext?> showTeachingContextSelector(
  BuildContext context, {
  required List<CurriculumClass> classes,
  required Map<String, List<String>> selectedSubjectsByClass,
  TeachingContext? initial,
}) {
  final configured = classes
      .where((c) {
        final subjects = selectedSubjectsByClass[c.code] ?? const <String>[];
        return subjects.any((code) => c.subjects.any((s) => s.code == code));
      })
      .toList(growable: false);
  if (configured.isEmpty) return Future.value(null);
  return showModalBottomSheet<TeachingContext>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TeachingContextSelectorSheet(
      classes: configured,
      selectedSubjectsByClass: selectedSubjectsByClass,
      initial: initial,
    ),
  );
}

class _TeachingContextSelectorSheet extends StatefulWidget {
  const _TeachingContextSelectorSheet({
    required this.classes,
    required this.selectedSubjectsByClass,
    this.initial,
  });
  final List<CurriculumClass> classes;
  final Map<String, List<String>> selectedSubjectsByClass;
  final TeachingContext? initial;

  @override
  State<_TeachingContextSelectorSheet> createState() =>
      _TeachingContextSelectorSheetState();
}

class _TeachingContextSelectorSheetState
    extends State<_TeachingContextSelectorSheet> {
  late CurriculumClass _class;
  CurriculumSubject? _subject;

  @override
  void initState() {
    super.initState();
    _class = widget.classes.firstWhere(
      (c) => c.code == widget.initial?.classCode,
      orElse: () => widget.classes.first,
    );
    _syncSubject(preferred: widget.initial?.subjectCode);
  }

  List<CurriculumSubject> get _subjects {
    final allowed =
        widget.selectedSubjectsByClass[_class.code] ?? const <String>[];
    return _class.subjects
        .where((s) => allowed.contains(s.code))
        .toList(growable: false);
  }

  void _syncSubject({String? preferred}) {
    final subjects = _subjects;
    if (subjects.isEmpty) {
      _subject = null;
    } else {
      _subject = subjects.firstWhere(
        (s) => s.code == preferred,
        orElse: () => subjects.first,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _subjects;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.classes.length > 1) ...[
              Text('Class', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final item in widget.classes)
                    ChoiceChip(
                      label: Text(item.name),
                      selected: item.code == _class.code,
                      onSelected: (_) => setState(() {
                        _class = item;
                        _syncSubject();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (subjects.length > 1) ...[
              Text('Subject', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final item in subjects)
                    ChoiceChip(
                      label: Text(item.name),
                      selected: item.code == _subject?.code,
                      onSelected: (_) => setState(() => _subject = item),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            FilledButton(
              onPressed: _subject == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      TeachingContext(
                        classCode: _class.code,
                        className: _class.name,
                        subjectCode: _subject!.code,
                        subjectName: _subject!.name,
                      ),
                    ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
