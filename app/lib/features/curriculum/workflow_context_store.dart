import 'teaching_context.dart';

class WorkflowContextStore {
  TeachingContext? _lesson;
  TeachingContext? _test;

  TeachingContext? lastFor(String workflow) =>
      workflow == 'lesson' ? _lesson : _test;

  void save(String workflow, TeachingContext context) {
    if (workflow == 'lesson') {
      _lesson = context;
    } else {
      _test = context;
    }
  }
}
