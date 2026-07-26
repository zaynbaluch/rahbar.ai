import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../generation/mcq_parser.dart';
import 'omr_grader.dart';

typedef OmrImageWorker = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> message,
);

/// Decodes and grades a photographed answer sheet away from the UI isolate.
class OmrImageProcessor {
  OmrImageProcessor({OmrImageWorker? worker})
      : _worker = worker ?? _runWorker;

  final OmrImageWorker _worker;

  Future<OmrResult> process(Uint8List bytes, McqTest test) async {
    final result = await _worker({
      'bytes': TransferableTypedData.fromList([bytes]),
      'test': test.toJson(),
    });
    return OmrResult.fromJson(result);
  }

  static Future<Map<String, dynamic>> _runWorker(
    Map<String, dynamic> message,
  ) =>
      compute(processOmrImage, message);
}

/// Isolate entry point. Keep this top-level so Flutter can run it with [compute].
Map<String, dynamic> processOmrImage(Map<String, dynamic> message) {
  final transferable = message['bytes'] as TransferableTypedData;
  final bytes = transferable.materialize().asUint8List();
  final test = McqTest.fromJson(
    Map<String, dynamic>.from(message['test'] as Map),
  );

  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Could not read the selected image.');
  }
  decoded = img.bakeOrientation(decoded);
  if (decoded.width > 2000 || decoded.height > 2000) {
    decoded = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 2000 : null,
      height: decoded.height > decoded.width ? 2000 : null,
    );
  }
  return OmrGrader.grade(decoded, test).toJson();
}
