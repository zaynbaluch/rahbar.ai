import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../generation/mcq_parser.dart';

/// Renders a parsed [McqTest] to a printable PDF: a student **test paper**, an
/// **OMR answer sheet** (bubbles + corner fiducial markers for the future camera
/// grader), and a teacher **answer key**. The test ID ties a scanned sheet back to
/// its stored key so grading needs no SLM (see the assessment/OMR plan, ADR-007).
class PdfExport {
  static const _letters = ['A', 'B', 'C', 'D'];

  /// Short, human-readable test ID (also printed on the OMR sheet for grading).
  static String testId(String topic) {
    final h = topic.hashCode & 0xffff;
    return 'GS6-${h.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  static Future<Uint8List> build(McqTest test) async {
    final doc = pw.Document();
    final id = testId(test.topic);
    final complete = test.questions.where((q) => q.isComplete).toList();

    doc.addPage(_paperPage(test, id, complete));
    doc.addPage(_omrPage(id, complete.length));
    doc.addPage(_keyPage(test, id, complete));
    return doc.save();
  }

  // ---- Page 1: the test paper ----
  static pw.Page _paperPage(McqTest test, String id, List<McqQuestion> qs) {
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        _header('Test Paper', test.topic, id),
        pw.SizedBox(height: 8),
        _studentFields(),
        pw.Divider(),
        pw.Text(
          'Instructions: Choose the ONE best answer for each question and mark it '
          'on the answer sheet. Time: 50 minutes.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 10),
        for (var i = 0; i < qs.length; i++) _question(i + 1, qs[i]),
      ],
    );
  }

  static pw.Widget _question(int n, McqQuestion q) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$n. ${q.text}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final l in _letters)
            if (q.options.containsKey(l))
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 14, bottom: 2),
                child: pw.Text('($l)  ${q.options[l]}',
                    style: const pw.TextStyle(fontSize: 10)),
              ),
        ],
      ),
    );
  }

  // ---- Page 2: the OMR answer sheet ----
  static pw.Page _omrPage(String id, int n) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Stack(
        children: [
          // Corner fiducial markers — registration points for the camera grader.
          ..._fiducials(),
          pw.Padding(
            // Clear the corner fiducial markers so they never overlap the header.
            padding: const pw.EdgeInsets.only(top: 20),
            child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _header('Answer Sheet (OMR)', 'Fill one bubble per question', id),
              pw.SizedBox(height: 8),
              _studentFields(),
              pw.SizedBox(height: 4),
              pw.Text(
                'Fill the bubble completely with a dark pen. Mark only ONE per row.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 16),
              pw.Wrap(
                spacing: 40,
                runSpacing: 12,
                children: [for (var i = 1; i <= n; i++) _bubbleRow(i)],
              ),
            ],
          ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _bubbleRow(int n) {
    return pw.SizedBox(
      width: 200,
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 28,
            child: pw.Text('Q$n',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          for (final l in _letters)
            pw.Padding(
              padding: const pw.EdgeInsets.only(right: 8),
              child: pw.Column(
                children: [
                  pw.Container(
                    width: 16,
                    height: 16,
                    decoration: pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(width: 1, color: PdfColors.black),
                    ),
                  ),
                  pw.Text(l, style: const pw.TextStyle(fontSize: 7)),
                ],
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
          child: pw.Container(width: s, height: s, color: PdfColors.black),
        );
    return [
      marker(pw.Alignment.topLeft),
      marker(pw.Alignment.topRight),
      marker(pw.Alignment.bottomLeft),
      marker(pw.Alignment.bottomRight),
    ];
  }

  // ---- Page 3: teacher answer key ----
  static pw.Page _keyPage(McqTest test, String id, List<McqQuestion> qs) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Answer Key (Teacher Copy)', test.topic, id),
          pw.SizedBox(height: 16),
          pw.Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              for (final q in qs)
                pw.Text('Q${q.number}:  ${q.answer ?? '?'}',
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  // ---- shared bits ----
  static pw.Widget _header(String kind, String subtitle, String id) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Rahbar AI - General Science, Grade 6',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text('Test ID: $id',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
        ),
        pw.Text('$kind: $subtitle',
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
        field('Name', 140),
        pw.SizedBox(width: 16),
        field('Roll No', 70),
        pw.SizedBox(width: 16),
        field('Date', 80),
      ],
    );
  }
}
