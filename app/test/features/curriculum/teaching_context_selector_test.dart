import 'package:bayaz_ai/features/curriculum/curriculum_catalog.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context.dart';
import 'package:bayaz_ai/features/curriculum/teaching_context_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const classes = [
    CurriculumClass(
      code: '6',
      name: 'Class 6',
      subjects: [
        CurriculumSubject(
          code: 'science',
          name: 'Science',
          moduleId: 's6',
          description: '',
        ),
        CurriculumSubject(
          code: 'math',
          name: 'Math',
          moduleId: 'm6',
          description: '',
        ),
      ],
    ),
    CurriculumClass(
      code: '7',
      name: 'Class 7',
      subjects: [
        CurriculumSubject(
          code: 'science',
          name: 'Science',
          moduleId: 's7',
          description: '',
        ),
      ],
    ),
  ];

  testWidgets('selector auto-selects the only subject for a class', (
    tester,
  ) async {
    TeachingContext? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  result = await showTeachingContextSelector(
                    context,
                    classes: classes,
                    selectedSubjectsByClass: const {
                      '6': ['science', 'math'],
                      '7': ['science'],
                    },
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Class 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result?.classCode, '7');
    expect(result?.subjectCode, 'science');
  });
}
