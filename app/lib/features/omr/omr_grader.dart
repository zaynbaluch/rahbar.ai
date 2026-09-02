import 'package:image/image.dart' as img;

import '../generation/mcq_parser.dart';
import 'omr_pipeline.dart';
import 'omr_result.dart';

export 'omr_result.dart';

/// Compatibility facade for the grading flow. The implementation lives in the
/// staged [OmrPipeline], while existing callers keep the stable `grade` entry point.
abstract final class OmrGrader {
  static OmrResult grade(img.Image image, McqTest key) =>
      OmrPipeline.scan(image, key);
}
