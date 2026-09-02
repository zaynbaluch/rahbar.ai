enum OmrScanStatus { complete, rejected }

enum OmrFailureCode {
  none,
  imageTooSmall,
  fiducialsNotFound,
  invalidFiducialGeometry,
  templateMismatch,
}

enum OmrDecisionKind { marked, blank, ambiguous }

T _enumByName<T extends Enum>(Iterable<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

OmrDecisionKind omrDecisionKindFromWire(Object? raw, {String? marked}) =>
    _enumByName(
      OmrDecisionKind.values,
      raw,
      marked == null ? OmrDecisionKind.blank : OmrDecisionKind.marked,
    );

class OmrPoint {
  const OmrPoint(this.x, this.y);
  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory OmrPoint.fromJson(Map<String, dynamic> json) =>
      OmrPoint((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}

class OmrBubbleDiagnostic {
  const OmrBubbleDiagnostic({
    required this.option,
    required this.interiorDarkness,
    required this.backgroundDarkness,
    required this.localContrast,
    required this.darkPixelDensity,
    required this.score,
  });

  final String option;
  final double interiorDarkness;
  final double backgroundDarkness;
  final double localContrast;
  final double darkPixelDensity;
  final double score;

  Map<String, dynamic> toJson() => {
    'option': option,
    'interiorDarkness': interiorDarkness,
    'backgroundDarkness': backgroundDarkness,
    'localContrast': localContrast,
    'darkPixelDensity': darkPixelDensity,
    'score': score,
  };

  factory OmrBubbleDiagnostic.fromJson(Map<String, dynamic> json) =>
      OmrBubbleDiagnostic(
        option: json['option'] as String,
        interiorDarkness: (json['interiorDarkness'] as num).toDouble(),
        backgroundDarkness: (json['backgroundDarkness'] as num).toDouble(),
        localContrast: (json['localContrast'] as num).toDouble(),
        darkPixelDensity: (json['darkPixelDensity'] as num).toDouble(),
        score: (json['score'] as num).toDouble(),
      );
}

class OmrRowDiagnostic {
  const OmrRowDiagnostic({
    required this.questionNumber,
    required this.bubbles,
    required this.decision,
    required this.marked,
    required this.confidence,
    required this.reason,
  });

  final int questionNumber;
  final List<OmrBubbleDiagnostic> bubbles;
  final OmrDecisionKind decision;
  final String? marked;
  final double confidence;
  final String reason;

  Map<String, dynamic> toJson() => {
    'questionNumber': questionNumber,
    'bubbles': bubbles.map((bubble) => bubble.toJson()).toList(),
    'decision': decision.name,
    'marked': marked,
    'confidence': confidence,
    'reason': reason,
  };

  factory OmrRowDiagnostic.fromJson(Map<String, dynamic> json) =>
      OmrRowDiagnostic(
        questionNumber: json['questionNumber'] as int,
        bubbles: (json['bubbles'] as List? ?? const [])
            .map(
              (bubble) => OmrBubbleDiagnostic.fromJson(
                Map<String, dynamic>.from(bubble as Map),
              ),
            )
            .toList(growable: false),
        decision: omrDecisionKindFromWire(
          json['decision'],
          marked: json['marked'] as String?,
        ),
        marked: json['marked'] as String?,
        confidence: (json['confidence'] as num? ?? 0).toDouble(),
        reason: json['reason'] as String? ?? '',
      );
}

class OmrDiagnostics {
  const OmrDiagnostics({
    required this.status,
    required this.failureCode,
    required this.sourceWidth,
    required this.sourceHeight,
    this.canonicalWidth,
    this.canonicalHeight,
    this.meanLuminance = 0,
    this.darkClipFraction = 0,
    this.lightClipFraction = 0,
    this.blurVariance = 0,
    this.warnings = const [],
    this.markerCandidateCount = 0,
    this.fiducials = const [],
    this.registrationScore = 0,
    this.registrationNote = '',
    this.stageTimingsMs = const {},
    this.templateMatchScore = 0,
    this.templateMatchedBubbles = 0,
    this.templateExpectedBubbles = 0,
    this.templateNote = '',
    this.blankBaseline = 0,
    this.blankMad = 0,
    this.markThreshold = 0,
    this.rows = const [],
  });

  final OmrScanStatus status;
  final OmrFailureCode failureCode;
  final int sourceWidth;
  final int sourceHeight;
  final int? canonicalWidth;
  final int? canonicalHeight;
  final double meanLuminance;
  final double darkClipFraction;
  final double lightClipFraction;
  final double blurVariance;
  final List<String> warnings;
  final int markerCandidateCount;
  final List<OmrPoint> fiducials;
  final double registrationScore;
  final String registrationNote;
  final Map<String, int> stageTimingsMs;
  final double templateMatchScore;
  final int templateMatchedBubbles;
  final int templateExpectedBubbles;
  final String templateNote;
  final double blankBaseline;
  final double blankMad;
  final double markThreshold;
  final List<OmrRowDiagnostic> rows;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'failureCode': failureCode.name,
    'sourceWidth': sourceWidth,
    'sourceHeight': sourceHeight,
    if (canonicalWidth != null) 'canonicalWidth': canonicalWidth,
    if (canonicalHeight != null) 'canonicalHeight': canonicalHeight,
    'meanLuminance': meanLuminance,
    'darkClipFraction': darkClipFraction,
    'lightClipFraction': lightClipFraction,
    'blurVariance': blurVariance,
    'warnings': warnings,
    'markerCandidateCount': markerCandidateCount,
    'fiducials': fiducials.map((point) => point.toJson()).toList(),
    'registrationScore': registrationScore,
    'registrationNote': registrationNote,
    'stageTimingsMs': stageTimingsMs,
    'templateMatchScore': templateMatchScore,
    'templateMatchedBubbles': templateMatchedBubbles,
    'templateExpectedBubbles': templateExpectedBubbles,
    'templateNote': templateNote,
    'blankBaseline': blankBaseline,
    'blankMad': blankMad,
    'markThreshold': markThreshold,
    'rows': rows.map((row) => row.toJson()).toList(),
  };

  factory OmrDiagnostics.fromJson(Map<String, dynamic> json) => OmrDiagnostics(
    status: _enumByName(
      OmrScanStatus.values,
      json['status'],
      OmrScanStatus.rejected,
    ),
    failureCode: _enumByName(
      OmrFailureCode.values,
      json['failureCode'],
      OmrFailureCode.none,
    ),
    sourceWidth: json['sourceWidth'] as int? ?? 0,
    sourceHeight: json['sourceHeight'] as int? ?? 0,
    canonicalWidth: json['canonicalWidth'] as int?,
    canonicalHeight: json['canonicalHeight'] as int?,
    meanLuminance: (json['meanLuminance'] as num? ?? 0).toDouble(),
    darkClipFraction: (json['darkClipFraction'] as num? ?? 0).toDouble(),
    lightClipFraction: (json['lightClipFraction'] as num? ?? 0).toDouble(),
    blurVariance: (json['blurVariance'] as num? ?? 0).toDouble(),
    warnings: (json['warnings'] as List? ?? const [])
        .map((warning) => warning.toString())
        .toList(growable: false),
    markerCandidateCount: json['markerCandidateCount'] as int? ?? 0,
    fiducials: (json['fiducials'] as List? ?? const [])
        .map(
          (point) => OmrPoint.fromJson(Map<String, dynamic>.from(point as Map)),
        )
        .toList(growable: false),
    registrationScore: (json['registrationScore'] as num? ?? 0).toDouble(),
    registrationNote: json['registrationNote'] as String? ?? '',
    stageTimingsMs: (json['stageTimingsMs'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), (value as num).toInt()),
    ),
    templateMatchScore: (json['templateMatchScore'] as num? ?? 0).toDouble(),
    templateMatchedBubbles: json['templateMatchedBubbles'] as int? ?? 0,
    templateExpectedBubbles: json['templateExpectedBubbles'] as int? ?? 0,
    templateNote: json['templateNote'] as String? ?? '',
    blankBaseline: (json['blankBaseline'] as num? ?? 0).toDouble(),
    blankMad: (json['blankMad'] as num? ?? 0).toDouble(),
    markThreshold: (json['markThreshold'] as num? ?? 0).toDouble(),
    rows: (json['rows'] as List? ?? const [])
        .map(
          (row) =>
              OmrRowDiagnostic.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false),
  );

  String toReport() {
    String f(double value) => value.toStringAsFixed(3);
    final buffer = StringBuffer()
      ..writeln('Bayaz OMR diagnostics')
      ..writeln('status=${status.name} failure=${failureCode.name}')
      ..writeln('source=${sourceWidth}x$sourceHeight')
      ..writeln('canonical=${canonicalWidth ?? '-'}x${canonicalHeight ?? '-'}')
      ..writeln(
        'quality mean=${f(meanLuminance)} darkClip=${f(darkClipFraction)} '
        'lightClip=${f(lightClipFraction)} blur=${f(blurVariance)}',
      )
      ..writeln(
        'markers candidates=$markerCandidateCount score=${f(registrationScore)} note=${registrationNote.isEmpty ? '-' : registrationNote}',
      );
    if (stageTimingsMs.isNotEmpty) {
      buffer.writeln(
        'timings=${stageTimingsMs.entries.map((entry) => '${entry.key}:${entry.value}ms').join(' ')}',
      );
    }
    if (fiducials.isNotEmpty) {
      buffer.writeln(
        'fiducials=${fiducials.map((point) => '(${point.x.toStringAsFixed(1)},${point.y.toStringAsFixed(1)})').join(' ')}',
      );
    }
    if (templateExpectedBubbles > 0 || templateNote.isNotEmpty) {
      buffer.writeln(
        'template score=${f(templateMatchScore)} matched=$templateMatchedBubbles/$templateExpectedBubbles note=${templateNote.isEmpty ? '-' : templateNote}',
      );
    }
    buffer.writeln(
      'calibration blank=${f(blankBaseline)} mad=${f(blankMad)} threshold=${f(markThreshold)}',
    );
    if (warnings.isNotEmpty) buffer.writeln('warnings=${warnings.join(' | ')}');
    for (final row in rows) {
      final scores = row.bubbles
          .map((bubble) => '${bubble.option}=${f(bubble.score)}')
          .join(' ');
      buffer.writeln(
        'Q${row.questionNumber} marked=${row.marked ?? '-'} '
        'decision=${row.decision.name} conf=${f(row.confidence)} '
        'reason=${row.reason} scores[$scores]',
      );
    }
    return buffer.toString().trimRight();
  }
}
