import 'package:bayaz_ai/features/generation/lesson_plan_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the strict generated Markdown into a structured plan', () {
    const markdown = '''
### Objectives
- Identify renewable resources.
- Compare renewable and non-renewable resources.

### Materials
- Chalk
- Scrap paper

### Revision starter (5 min)
1. What is a natural resource?

### Engage (5 min)
Ask where electricity comes from.

### Explore (12 min)
Groups sort examples.

### Explain (12 min)
Explain the curriculum concept.

### Socratic questions
- Why might a resource run out?

### Elaborate (8 min)
Apply the idea at home.

### Evaluate (8 min)
Three exit questions.

### Homework
List two examples.

### Notes
Keep groups large.
''';

    final result = LessonPlanParser.parse(markdown, topic: 'Resources');

    expect(result.isComplete, isTrue);
    expect(result.plan.slos, hasLength(2));
    expect(result.plan.sectionOf('explore')!.minutes, 12);
    expect(result.plan.materials, containsAll(['Chalk', 'Scrap paper']));
  });

  test('reports required sections instead of inventing them', () {
    final result = LessonPlanParser.parse(
      '### Objectives\n- Explain the topic.',
      topic: 'Partial',
    );

    expect(result.missingSections, contains('engage'));
    expect(result.plan.sectionOf('engage'), isNull);
  });
}
