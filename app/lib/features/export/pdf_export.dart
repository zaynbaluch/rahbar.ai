import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../generation/mcq_parser.dart';

/// Renders a parsed [McqTest] to a single printable **test paper**: questions on
/// the left, a compact **OMR answer grid** (A–D bubbles) boxed on the top-right of
/// the same sheet — so no separate answer sheet is wasted. Corner fiducial markers
/// on the first page let the future camera grader register the bubbles. The answer
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
    return pw.MultiPage(
      // Fiducial markers only on the first page (the one the grader photographs).
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        buildBackground: (context) => context.pageNumber == 1
            ? pw.FullPage(ignoreMargins: true, child: pw.Stack(children: _fiducials()))
            : pw.SizedBox(),
      ),
      build: (context) => [
        // Top block: test info on the left, the answer bubble grid boxed on the right.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _header('Test Paper', test.topic, id),
                  pw.SizedBox(height: 8),
                  _studentFields(),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Choose the ONE best answer for each question and fill the '
                    'matching bubble in the answer grid. Time: 50 minutes.',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 14),
            _answerGrid(qs.length),
          ],
        ),
        pw.Divider(height: 20),
        for (var i = 0; i < qs.length; i++) _question(i + 1, qs[i]),
      ],
    );
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

  // ---- OMR answer grid (top-right box) ----
  static pw.Widget _answerGrid(int n) {
    return pw.Container(
      width: 168,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.8, color: PdfColors.grey600),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('ANSWERS',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text('Fill one bubble per row with a dark pen.',
              style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          // Column labels
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 24),
            child: pw.Row(children: [
              for (final l in _letters)
                pw.SizedBox(
                    width: 30,
                    child: pw.Center(
                        child: pw.Text(l, style: const pw.TextStyle(fontSize: 7)))),
            ]),
          ),
          for (var i = 1; i <= n; i++) _bubbleRow(i),
        ],
      ),
    );
  }

  static pw.Widget _bubbleRow(int n) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 24,
            child: pw.Text('Q$n',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ),
          for (var i = 0; i < _letters.length; i++)
            pw.SizedBox(
              width: 30,
              child: pw.Center(
                child: pw.Container(
                  width: 13,
                  height: 13,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(width: 0.9, color: PdfColors.black),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static List<pw.Widget> _fiducials() {
    const s = 14.0;
    pw.Widget marker(pw.Alignment a) => pw.Align(
          alignment: a,
          child: pw.Container(
            margin: const pw.EdgeInsets.all(12),
            width: s,
            height: s,
            color: PdfColors.black,
          ),
        );
    return [
      marker(pw.Alignment.topLeft),
      marker(pw.Alignment.topRight),
      marker(pw.Alignment.bottomLeft),
      marker(pw.Alignment.bottomRight),
    ];
  }

  // ---- shared bits ----
  static pw.Widget _header(String kind, String subtitle, String id) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Rahbar AI - General Science, Grade 6',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.Text('$kind: $subtitle   ·   Test ID: $id',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
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
