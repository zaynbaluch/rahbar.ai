import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../generation/lesson_plan.dart';
import '../generation/mcq_parser.dart';
import '../omr/omr_template.dart';

/// Renders a parsed [McqTest] to a single printable **test paper**: questions on
/// the left, a compact **OMR answer grid** (A–D bubbles) boxed on the top-right of
/// the same sheet (no separate answer sheet). Fiducials + bubbles are drawn at
/// exact [OmrTemplate] coordinates so the camera grader can sample them. The answer
/// key is NOT printed (the teacher reads it in the app). The persistent test ID keeps
/// printed papers and saved grading results associated with the same paper; the teacher
/// still opens that exact test before using the current camera grader.
class InvalidMcqPaperException implements Exception {
  const InvalidMcqPaperException(this.issues);

  final List<String> issues;

  @override
  String toString() => issues.join(' ');
}

class PdfExport {
  static const _letters = ['A', 'B', 'C', 'D'];

  /// Persistent paper ID printed on the sheet and reused by the gradebook.
  static String testId(McqTest test) => test.id;

  static Future<Uint8List> build(McqTest test) async {
    final validation = test.validation;
    if (!validation.isReady) {
      throw InvalidMcqPaperException(validation.issues);
    }
    final doc = pw.Document();
    final id = testId(test);
    final qs = test.questions;
    doc.addPage(_paperPage(test, id, qs));
    return doc.save();
  }

  /// The teacher's 5E lesson plan (ADR-006). Plain A4, no OMR layer — this sheet is for
  /// the teacher's hand, not the camera, so none of the [OmrTemplate] geometry applies.
  static Future<Uint8List> buildLessonPlan(LessonPlan plan) async {
    final doc = pw.Document();
    final materials = plan.materials;

    doc.addPage(pw.MultiPage(
      pageTheme: const pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(36),
      ),
      build: (context) => [
        pw.Text(plan.topic,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(
          'Grade 6 · General Science · one ${plan.totalMinutes}-minute period · '
          'Single National Curriculum',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.Divider(height: 16),
        if (plan.slos.isNotEmpty) ...[
          pw.Text('Learning outcomes',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final s in plan.slos)
            pw.Bullet(text: s, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 8),
        ],
        if (materials.isNotEmpty) ...[
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: 'What to bring:  ',
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.TextSpan(
                    text: materials.join(' · '),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 10),
        ],
        for (final s in plan.sections) _planSection(s),
      ],
    ));
    return doc.save();
  }

  static pw.Widget _planSection(PlanSection s) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    LessonPlan.sectionTitles[s.section] ?? s.section,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                if (s.minutes > 0)
                  pw.Text('${s.minutes} min',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 3),
            pw.Text(s.body,
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.6)),
          ],
        ),
      );

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
        for (final question in qs) _question(question.number, question),
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
        pw.Text('Bayaz AI - General Science, Grade 6',
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
