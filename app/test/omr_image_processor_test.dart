import 'dart:isolate';
import 'dart:typed_data';

import 'package:bayaz_ai/features/generation/mcq_parser.dart';
import 'package:bayaz_ai/features/omr/omr_grader.dart';
import 'package:bayaz_ai/features/omr/omr_image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('sends image data and paper data through the worker boundary', () async {
    late Map<String, dynamic> received;
    final processor = OmrImageProcessor(worker: (message) async {
      received = message;
      return const OmrResult(
        fiducialsFound: true,
        questions: [
          OmrQuestion(
            number: 1,
            marked: 'A',
            correct: 'A',
            fill: 0.8,
            confidence: 0.5,
          ),
        ],
      ).toJson();
    });
    final test = McqTest(
      topic: 'Topic',
      questions: const [
        McqQuestion(
          number: 1,
          difficulty: 'easy',
          text: 'Question',
          options: {'A': 'One', 'B': 'Two', 'C': 'Three', 'D': 'Four'},
          answer: 'A',
        ),
      ],
    );

    final result = await processor.process(
      Uint8List.fromList(const [1, 2, 3]),
      test,
    );

    expect(received['bytes'], isA<TransferableTypedData>());
    expect((received['test'] as Map)['id'], test.id);
    expect(result.fiducialsFound, isTrue);
    expect(result.correct, 1);
  });

  test('worker decodes image bytes and returns a grading result', () {
    final image = img.Image(width: 100, height: 100);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final test = McqTest(
      topic: 'Topic',
      questions: const [
        McqQuestion(
          number: 1,
          difficulty: 'easy',
          text: 'Question',
          options: {'A': 'One', 'B': 'Two', 'C': 'Three', 'D': 'Four'},
          answer: 'A',
        ),
      ],
    );

    final json = processOmrImage({
      'bytes': TransferableTypedData.fromList([
        Uint8List.fromList(img.encodePng(image)),
      ]),
      'test': test.toJson(),
    });
    final result = OmrResult.fromJson(json);

    expect(result.fiducialsFound, isFalse);
    expect(result.total, 1);
  });

  test('grading results survive isolate serialization', () {
    const original = OmrResult(
      fiducialsFound: true,
      questions: [
        OmrQuestion(
          number: 1,
          marked: null,
          correct: 'B',
          fill: 0.2,
          confidence: 0.05,
          reviewed: true,
        ),
      ],
    );

    final restored = OmrResult.fromJson(original.toJson());

    expect(restored.fiducialsFound, isTrue);
    expect(restored.questions.single.number, 1);
    expect(restored.questions.single.marked, isNull);
    expect(restored.questions.single.correct, 'B');
    expect(restored.questions.single.reviewed, isTrue);
  });
}
