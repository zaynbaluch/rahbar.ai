import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../generation/mcq_parser.dart';
import '../omr/omr_template.dart';

/// Renders a parsed [McqTest] to a single printable **test paper**: questions on
/// the left, a compact **OMR answer grid** (A–D bubbles) boxed on the top-right of
/// the same sheet (no separate answer sheet). Fiducials + bubbles are drawn at
/// exact [OmrTemplate] coordinates so the camera grader can sample them. The answer
/// key is NOT printed (the teacher reads it in the app); the test ID ties a scanned
/// sheet back to its stored key so grading needs no SLM (see ADR-007).
class PdfExport {
  static const _letters = ['A', 'B', 'C', 'D'];

  /// Short, human-readable test ID (printed on the sheet, used for grading lookup).
  static String testId(String topic) {
    final h = topic.hashCode & 0xffff;
    return 'GS6-${h.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  static Future<Uint8List> build(McqTest test) async {
    final doc = pw.Document();
    final id = testId(test.topic);
    final qs = test.questions.where((q) => q.isComplete).toList();
    doc.addPage(_paperPage(test, id, qs));
    return doc.save();
  }

  static pw.Page _paperPage(McqTest test, String id, List<McqQuestion> qs) {
    final n = qs.length;
    return pw.MultiPage(
      // The OMR layer (fiducials + bubbles) is drawn in the page foreground at
      // absolute OmrTemplate coordinates, only on page 1 (the graded page).
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        buildForeground: (context) =>
            context.pageNumber == 1 ? _omrLayer(n) : pw.SizedBox(),
      ),
      build: (context) => [
        // Reserve the top-right block where the OMR grid is drawn on top.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _header(test.topic, id),
                  pw.SizedBox(height: 10),
                  _studentFields(),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'Choose the ONE best answer and fill the matching bubble in the '
                    'answer grid. Time: 50 minutes.',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: OmrTemplate.boxW + 12, height: OmrTemplate.boxH + 8),
          ],
        ),
        pw.Divider(height: 18),
        for (var i = 0; i < n; i++) _question(i + 1, qs[i]),
      ],
    );
  }

  // ---- OMR foreground: fiducials + boxed bubble grid at absolute coords ----
  static pw.Widget _omrLayer(int n) {
    final children = <pw.Widget>[];

    // Corner fiducial markers.
    for (final (fx, fy) in OmrTemplate.fiducials) {
      children.add(pw.Positioned(
        left: fx - OmrTemplate.fidSize / 2,
        top: fy - OmrTemplate.fidSize / 2,
        child: pw.Container(
            width: OmrTemplate.fidSize,
            height: OmrTemplate.fidSize,
            color: PdfColors.black),
      ));
    }

    // Answer box.
    children.add(pw.Positioned(
      left: OmrTemplate.boxLeft,
      top: OmrTemplate.boxTop,
      child: pw.Container(
        width: OmrTemplate.boxW,
        height: OmrTemplate.boxH,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.8, color: PdfColors.grey600),
          borderRadius: pw.BorderRadius.circular(4),
        ),
      ),
    ));
    // Title above the box and a hint below it — outside the fiducial rectangle so
    // they never interfere with corner detection (and don't matter if the teacher
    // photographs just the box).
    children.add(pw.Positioned(
      left: OmrTemplate.boxLeft,
      top: OmrTemplate.boxTop - 13,
      child: pw.Text('ANSWERS  (photograph this box to grade)',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
    ));
    children.add(pw.Positioned(
      left: OmrTemplate.boxLeft,
      top: OmrTemplate.boxBottom + 3,
      child: pw.Text('Fill one bubble per row with a dark pen.',
          style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
    ));

    // Column labels A B C D.
    for (var c = 0; c < OmrTemplate.options; c++) {
      children.add(pw.Positioned(
        left: OmrTemplate.colX(c) - 2.5,
        top: OmrTemplate.colLabelY - 5,
        child: pw.Text(_letters[c], style: const pw.TextStyle(fontSize: 7)),
      ));
    }

    // Q labels + bubbles.
    for (var q = 1; q <= n; q++) {
      children.add(pw.Positioned(
        left: OmrTemplate.qLabelX,
        top: OmrTemplate.rowY(q) - 4,
        child: pw.Text('Q$q',
            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
      ));
      for (var c = 0; c < OmrTemplate.options; c++) {
        final (cx, cy) = OmrTemplate.bubbleCenter(q, c);
        children.add(pw.Positioned(
          left: cx - OmrTemplate.bubbleR,
          top: cy - OmrTemplate.bubbleR,
          child: pw.Container(
            width: OmrTemplate.bubbleR * 2,
            height: OmrTemplate.bubbleR * 2,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(width: 0.9, color: PdfColors.black),
            ),
          ),
        ));
      }
    }

    return pw.FullPage(ignoreMargins: true, child: pw.Stack(children: children));
  }

  // ---- Questions (left, flow down the page) ----
  static pw.Widget _question(int n, McqQuestion q) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$n. ${q.text}',
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          for (final l in _letters)
            if (q.options.containsKey(l))
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 14, bottom: 1),
                child: pw.Text('($l)  ${q.options[l]}',
                    style: const pw.TextStyle(fontSize: 9.5)),
              ),
        ],
      ),
    );
  }

  static pw.Widget _header(String topic, String id) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Rahbar AI - General Science, Grade 6',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.Text('Topic: $topic',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
        pw.Text('Test ID: $id',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ],
    );
  }

  static pw.Widget _studentFields() {
    pw.Widget field(String label, double w) => pw.Row(
          children: [
            pw.Text('$label: ', style: const pw.TextStyle(fontSize: 10)),
            pw.Container(
              width: w,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.8)),
              ),
              child: pw.SizedBox(height: 14),
            ),
          ],
        );
    return pw.Row(
      children: [
        field('Name', 150),
        pw.SizedBox(width: 16),
        field('Roll No', 70),
      ],
    );
  }
}
