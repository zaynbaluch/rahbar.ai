import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'omr_diagnostics.dart';
import 'omr_template.dart';

class OmrRegistrationHypothesis {
  const OmrRegistrationHypothesis({
    required this.fiducials,
    required this.score,
  });

  final List<OmrPoint> fiducials;
  final double score;
}

class OmrRegistrationResult {
  const OmrRegistrationResult({
    required this.failureCode,
    required this.candidateCount,
    required this.retainedCandidateCount,
    required this.hypotheses,
    required this.combinationsEvaluated,
    this.note = '',
  });

  final OmrFailureCode failureCode;
  final int candidateCount;
  final int retainedCandidateCount;
  final List<OmrRegistrationHypothesis> hypotheses;
  final int combinationsEvaluated;
  final String note;

  bool get success =>
      failureCode == OmrFailureCode.none && hypotheses.isNotEmpty;
  List<OmrPoint> get fiducials =>
      hypotheses.isEmpty ? const [] : hypotheses.first.fiducials;
  double get score => hypotheses.isEmpty ? 0 : hypotheses.first.score;
}

class _MarkerCandidate {
  const _MarkerCandidate({
    required this.center,
    required this.area,
    required this.width,
    required this.height,
    required this.fillRatio,
    required this.darkness,
    required this.score,
  });

  final OmrPoint center;
  final int area;
  final int width;
  final int height;
  final double fillRatio;
  final double darkness;
  final double score;
}

class _ScoredHypothesis {
  const _ScoredHypothesis({required this.fiducials, required this.score});

  final List<OmrPoint> fiducials;
  final double score;
}

class _HypothesisSearchResult {
  const _HypothesisSearchResult({
    required this.hypotheses,
    required this.combinationsEvaluated,
  });

  final List<_ScoredHypothesis> hypotheses;
  final int combinationsEvaluated;
}

abstract final class OmrRegistration {
  static const int maxRetainedCandidates = 48;
  static const int maxDirectionalPartners = 10;
  static const int maxBottomRightPartners = 4;
  static const int maxHypotheses = 8;

  static OmrRegistrationResult detect(img.Image gray, OmrLayout layout) {
    if (gray.width < 240 || gray.height < 240) {
      return const OmrRegistrationResult(
        failureCode: OmrFailureCode.imageTooSmall,
        candidateCount: 0,
        retainedCandidateCount: 0,
        hypotheses: [],
        combinationsEvaluated: 0,
        note: 'image dimensions are below the registration minimum',
      );
    }

    final maxDimension = math.max(gray.width, gray.height);
    final scale = maxDimension > 1000 ? 1000 / maxDimension : 1.0;
    final work = scale < 1
        ? img.copyResize(
            gray,
            width: (gray.width * scale).round(),
            height: (gray.height * scale).round(),
            interpolation: img.Interpolation.linear,
          )
        : gray;
    final candidates = _findCandidates(work);
    if (candidates.length < 4) {
      return OmrRegistrationResult(
        failureCode: OmrFailureCode.fiducialsNotFound,
        candidateCount: candidates.length,
        retainedCandidateCount: candidates.length,
        hypotheses: const [],
        combinationsEvaluated: 0,
        note:
            'only ${candidates.length} square-like marker candidates were found',
      );
    }

    final retained = [...candidates]
      ..sort((a, b) => b.score.compareTo(a.score));
    if (retained.length > maxRetainedCandidates) {
      retained.removeRange(maxRetainedCandidates, retained.length);
    }

    final search = _buildHypotheses(retained, work.width, work.height, layout);
    if (search.hypotheses.isEmpty) {
      return OmrRegistrationResult(
        failureCode: OmrFailureCode.invalidFiducialGeometry,
        candidateCount: candidates.length,
        retainedCandidateCount: retained.length,
        hypotheses: const [],
        combinationsEvaluated: search.combinationsEvaluated,
        note:
            'no plausible Bayaz-sized quadrilateral survived bounded geometry search; retained ${retained.length}/${candidates.length} candidates and evaluated ${search.combinationsEvaluated} combinations',
      );
    }

    final inverseScale = 1 / scale;
    final hypotheses = [
      for (final hypothesis in search.hypotheses)
        OmrRegistrationHypothesis(
          fiducials: [
            for (final point in hypothesis.fiducials)
              OmrPoint(point.x * inverseScale, point.y * inverseScale),
          ],
          score: hypothesis.score,
        ),
    ];
    return OmrRegistrationResult(
      failureCode: OmrFailureCode.none,
      candidateCount: candidates.length,
      retainedCandidateCount: retained.length,
      hypotheses: hypotheses,
      combinationsEvaluated: search.combinationsEvaluated,
      note:
          'bounded search retained ${retained.length}/${candidates.length} candidates, evaluated ${search.combinationsEvaluated} combinations, and kept ${hypotheses.length} geometric hypotheses',
    );
  }

  static _HypothesisSearchResult _buildHypotheses(
    List<_MarkerCandidate> candidates,
    int width,
    int height,
    OmrLayout layout,
  ) {
    final hypotheses = <_ScoredHypothesis>[];
    var combinationsEvaluated = 0;
    final minSpan = math.max(30.0, math.min(width, height) * .055);

    double sizeSimilarity(_MarkerCandidate a, _MarkerCandidate b) {
      return math.min(a.area, b.area) / math.max(a.area, b.area);
    }

    for (final tl in candidates) {
      final rights =
          candidates.where((candidate) {
            if (identical(candidate, tl)) return false;
            final dx = candidate.center.x - tl.center.x;
            final dy = candidate.center.y - tl.center.y;
            if (dx < minSpan) return false;
            if (dy.abs() > dx * .75 + minSpan * .25) return false;
            return sizeSimilarity(tl, candidate) >= .28;
          }).toList()..sort((a, b) {
            final aDx = a.center.x - tl.center.x;
            final aDy = (a.center.y - tl.center.y).abs();
            final bDx = b.center.x - tl.center.x;
            final bDy = (b.center.y - tl.center.y).abs();
            final aScore =
                a.score + sizeSimilarity(tl, a) * .35 - aDy / aDx * .25;
            final bScore =
                b.score + sizeSimilarity(tl, b) * .35 - bDy / bDx * .25;
            return bScore.compareTo(aScore);
          });
      if (rights.length > maxDirectionalPartners) {
        rights.removeRange(maxDirectionalPartners, rights.length);
      }

      final downs =
          candidates.where((candidate) {
            if (identical(candidate, tl)) return false;
            final dx = candidate.center.x - tl.center.x;
            final dy = candidate.center.y - tl.center.y;
            if (dy < minSpan) return false;
            if (dx.abs() > dy * .75 + minSpan * .25) return false;
            return sizeSimilarity(tl, candidate) >= .28;
          }).toList()..sort((a, b) {
            final aDy = a.center.y - tl.center.y;
            final aDx = (a.center.x - tl.center.x).abs();
            final bDy = b.center.y - tl.center.y;
            final bDx = (b.center.x - tl.center.x).abs();
            final aScore =
                a.score + sizeSimilarity(tl, a) * .35 - aDx / aDy * .25;
            final bScore =
                b.score + sizeSimilarity(tl, b) * .35 - bDx / bDy * .25;
            return bScore.compareTo(aScore);
          });
      if (downs.length > maxDirectionalPartners) {
        downs.removeRange(maxDirectionalPartners, downs.length);
      }

      for (final tr in rights) {
        for (final bl in downs) {
          if (identical(tr, bl)) continue;
          if (math.min(sizeSimilarity(tl, tr), sizeSimilarity(tl, bl)) < .28) {
            continue;
          }
          final predictedX = tr.center.x + bl.center.x - tl.center.x;
          final predictedY = tr.center.y + bl.center.y - tl.center.y;
          final topSpan = _distance(tl.center, tr.center);
          final leftSpan = _distance(tl.center, bl.center);
          final tolerance = math.max(
            minSpan,
            math.max(topSpan, leftSpan) * .48,
          );

          final bottomRights =
              candidates.where((candidate) {
                if (identical(candidate, tl) ||
                    identical(candidate, tr) ||
                    identical(candidate, bl)) {
                  return false;
                }
                if (candidate.center.x <= bl.center.x - minSpan * .25 ||
                    candidate.center.y <= tr.center.y - minSpan * .25) {
                  return false;
                }
                if (sizeSimilarity(tl, candidate) < .28) return false;
                final dx = candidate.center.x - predictedX;
                final dy = candidate.center.y - predictedY;
                return math.sqrt(dx * dx + dy * dy) <= tolerance;
              }).toList()..sort((a, b) {
                double rank(_MarkerCandidate candidate) {
                  final dx = candidate.center.x - predictedX;
                  final dy = candidate.center.y - predictedY;
                  final normalizedDistance =
                      math.sqrt(dx * dx + dy * dy) / tolerance;
                  return candidate.score +
                      sizeSimilarity(tl, candidate) * .30 -
                      normalizedDistance * .45;
                }

                return rank(b).compareTo(rank(a));
              });
          if (bottomRights.length > maxBottomRightPartners) {
            bottomRights.removeRange(
              maxBottomRightPartners,
              bottomRights.length,
            );
          }

          for (final br in bottomRights) {
            combinationsEvaluated++;
            final set = [tl, tr, br, bl];
            final geometry = _geometryScore(set, width, height, layout);
            if (geometry <= 0) continue;
            final candidateScore =
                set
                    .map((candidate) => candidate.score)
                    .reduce((a, b) => a + b) /
                4;
            final score = geometry * .68 + candidateScore * .32;
            hypotheses.add(
              _ScoredHypothesis(
                fiducials: [tl.center, tr.center, br.center, bl.center],
                score: score.clamp(0, 1).toDouble(),
              ),
            );
          }
        }
      }
    }

    hypotheses.sort((a, b) => b.score.compareTo(a.score));
    final unique = <_ScoredHypothesis>[];
    for (final hypothesis in hypotheses) {
      final duplicate = unique.any(
        (existing) => _sameHypothesis(existing.fiducials, hypothesis.fiducials),
      );
      if (duplicate) continue;
      unique.add(hypothesis);
      if (unique.length >= maxHypotheses) break;
    }
    return _HypothesisSearchResult(
      hypotheses: unique,
      combinationsEvaluated: combinationsEvaluated,
    );
  }

  static bool _sameHypothesis(List<OmrPoint> a, List<OmrPoint> b) {
    if (a.length != 4 || b.length != 4) return false;
    for (var i = 0; i < 4; i++) {
      if (_distance(a[i], b[i]) > 6) return false;
    }
    return true;
  }

  static double _distance(OmrPoint a, OmrPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static List<_MarkerCandidate> _findCandidates(img.Image gray) {
    final width = gray.width;
    final height = gray.height;
    final tileSize = math.max(32, math.min(width, height) ~/ 12);
    final tilesX = (width + tileSize - 1) ~/ tileSize;
    final tilesY = (height + tileSize - 1) ~/ tileSize;
    final tileSums = Float64List(tilesX * tilesY);
    final tileCounts = Int32List(tilesX * tilesY);
    for (var y = 0; y < height; y++) {
      final ty = y ~/ tileSize;
      for (var x = 0; x < width; x++) {
        final tx = x ~/ tileSize;
        final index = ty * tilesX + tx;
        tileSums[index] += gray.getPixel(x, y).luminance.toDouble();
        tileCounts[index]++;
      }
    }

    double localMean(int x, int y) {
      final tx = x ~/ tileSize;
      final ty = y ~/ tileSize;
      double sum = 0;
      var count = 0;
      for (var oy = -1; oy <= 1; oy++) {
        final yy = ty + oy;
        if (yy < 0 || yy >= tilesY) continue;
        for (var ox = -1; ox <= 1; ox++) {
          final xx = tx + ox;
          if (xx < 0 || xx >= tilesX) continue;
          final index = yy * tilesX + xx;
          sum += tileSums[index];
          count += tileCounts[index];
        }
      }
      return count == 0 ? 255 : sum / count;
    }

    final mask = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final lum = gray.getPixel(x, y).luminance.toDouble();
        final mean = localMean(x, y);
        if (lum < 82 || lum < mean - 52) mask[y * width + x] = 1;
      }
    }

    // The shipping PDF draws a thin answer-box border through the fiducial
    // centers. Remove thin strokes before connected-component extraction so that
    // the border cannot glue all four solid squares into one giant component.
    // Filled squares survive this small erosion; thin print/borders do not.
    final erosionRadius = (math.min(width, height) * .003).round().clamp(1, 3);
    final componentMask = _erodeMask(mask, width, height, erosionRadius);

    final visited = Uint8List(width * height);
    final queue = <int>[];
    final candidates = <_MarkerCandidate>[];
    final minArea = math.max(24, (width * height * .00005).round());
    final maxArea = math.max(minArea + 1, (width * height * .025).round());

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final start = y * width + x;
        if (componentMask[start] == 0 || visited[start] != 0) continue;
        queue
          ..clear()
          ..add(start);
        visited[start] = 1;
        var head = 0;
        var area = 0;
        var minX = x;
        var maxX = x;
        var minY = y;
        var maxY = y;
        double sumX = 0;
        double sumY = 0;
        double sumDark = 0;
        while (head < queue.length) {
          final index = queue[head++];
          final px = index % width;
          final py = index ~/ width;
          area++;
          minX = math.min(minX, px);
          maxX = math.max(maxX, px);
          minY = math.min(minY, py);
          maxY = math.max(maxY, py);
          final darkness = 255 - gray.getPixel(px, py).luminance.toDouble();
          sumX += px * darkness;
          sumY += py * darkness;
          sumDark += darkness;
          for (var oy = -1; oy <= 1; oy++) {
            for (var ox = -1; ox <= 1; ox++) {
              if (ox == 0 && oy == 0) continue;
              final nx = px + ox;
              final ny = py + oy;
              if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
              final next = ny * width + nx;
              if (componentMask[next] == 0 || visited[next] != 0) continue;
              visited[next] = 1;
              queue.add(next);
            }
          }
        }
        if (area < minArea || area > maxArea) continue;
        final boxW = maxX - minX + 1;
        final boxH = maxY - minY + 1;
        if (boxW < 6 || boxH < 6) continue;
        final square = math.min(boxW, boxH) / math.max(boxW, boxH);
        final fill = area / (boxW * boxH);
        if (square < .58 || fill < .46) continue;
        final avgDarkness = sumDark == 0 ? 0.0 : sumDark / (area * 255.0);
        if (avgDarkness < .50) continue;
        final cx = sumDark == 0 ? (minX + maxX) / 2 : sumX / sumDark;
        final cy = sumDark == 0 ? (minY + maxY) / 2 : sumY / sumDark;
        final normalizedArea = area / (width * height);
        final sizeScore = (normalizedArea / .0012).clamp(0.0, 1.0);
        final score =
            square * .30 +
            fill.clamp(0.0, 1.0) * .30 +
            avgDarkness.clamp(0.0, 1.0) * .25 +
            sizeScore * .15;
        candidates.add(
          _MarkerCandidate(
            center: OmrPoint(cx, cy),
            area: area,
            width: boxW,
            height: boxH,
            fillRatio: fill,
            darkness: avgDarkness,
            score: score.clamp(0, 1).toDouble(),
          ),
        );
      }
    }
    return candidates;
  }

  static Uint8List _erodeMask(
    Uint8List mask,
    int width,
    int height,
    int radius,
  ) {
    if (radius <= 0) return Uint8List.fromList(mask);
    final out = Uint8List(width * height);
    for (var y = radius; y < height - radius; y++) {
      for (var x = radius; x < width - radius; x++) {
        var solid = true;
        for (var oy = -radius; oy <= radius && solid; oy++) {
          final row = (y + oy) * width;
          for (var ox = -radius; ox <= radius; ox++) {
            if (mask[row + x + ox] == 0) {
              solid = false;
              break;
            }
          }
        }
        if (solid) out[y * width + x] = 1;
      }
    }
    return out;
  }

  static double _geometryScore(
    List<_MarkerCandidate> set,
    int width,
    int height,
    OmrLayout layout,
  ) {
    final tl = set[0].center;
    final tr = set[1].center;
    final br = set[2].center;
    final bl = set[3].center;
    if (tl.x >= tr.x || bl.x >= br.x || tl.y >= bl.y || tr.y >= br.y) return 0;

    double dist(OmrPoint a, OmrPoint b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
    final top = dist(tl, tr);
    final right = dist(tr, br);
    final bottom = dist(bl, br);
    final left = dist(tl, bl);
    final minimumEdge = math.max(28.0, math.min(width, height) * .05);
    if (top < minimumEdge || bottom < minimumEdge) return 0;
    if (left < minimumEdge || right < minimumEdge) return 0;
    final horizontalConsistency = math.min(top, bottom) / math.max(top, bottom);
    final verticalConsistency = math.min(left, right) / math.max(left, right);
    if (horizontalConsistency < .28 || verticalConsistency < .28) return 0;

    final areas = set.map((candidate) => candidate.area).toList()..sort();
    final sizeConsistency = areas.first / areas.last;
    if (sizeConsistency < .30) return 0;

    final polygonArea =
        ((tl.x * tr.y - tr.x * tl.y) +
                (tr.x * br.y - br.x * tr.y) +
                (br.x * bl.y - bl.x * br.y) +
                (bl.x * tl.y - tl.x * bl.y))
            .abs() /
        2;
    final areaFraction = polygonArea / (width * height);
    if (areaFraction < .012) return 0;

    final observedAspect = ((top + bottom) / 2) / ((left + right) / 2);
    final expectedAspect = layout.boxW / layout.boxH;
    final aspectRatio = observedAspect / expectedAspect;
    final aspectScore = math.exp(-.55 * math.log(aspectRatio).abs());
    final areaScore = (areaFraction / .18).clamp(0.0, 1.0);
    return (horizontalConsistency * .22 +
            verticalConsistency * .22 +
            sizeConsistency * .20 +
            aspectScore * .20 +
            areaScore * .16)
        .clamp(0, 1)
        .toDouble();
  }
}
