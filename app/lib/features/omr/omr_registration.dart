import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'omr_diagnostics.dart';
import 'omr_template.dart';

class OmrRegistrationResult {
  const OmrRegistrationResult({
    required this.failureCode,
    required this.candidateCount,
    required this.fiducials,
    required this.score,
  });

  final OmrFailureCode failureCode;
  final int candidateCount;
  final List<OmrPoint> fiducials;
  final double score;

  bool get success =>
      failureCode == OmrFailureCode.none && fiducials.length == 4;
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

abstract final class OmrRegistration {
  static OmrRegistrationResult detect(img.Image gray, OmrLayout layout) {
    if (gray.width < 240 || gray.height < 240) {
      return const OmrRegistrationResult(
        failureCode: OmrFailureCode.imageTooSmall,
        candidateCount: 0,
        fiducials: [],
        score: 0,
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
        fiducials: const [],
        score: 0,
      );
    }

    final quadrants = List.generate(4, (_) => <_MarkerCandidate>[]);
    final midX = work.width / 2;
    final midY = work.height / 2;
    for (final candidate in candidates) {
      final left = candidate.center.x < midX;
      final top = candidate.center.y < midY;
      final quadrant = top ? (left ? 0 : 1) : (left ? 3 : 2);
      quadrants[quadrant].add(candidate);
    }
    for (final group in quadrants) {
      group.sort((a, b) => b.score.compareTo(a.score));
      if (group.length > 8) group.removeRange(8, group.length);
    }
    if (quadrants.any((group) => group.isEmpty)) {
      return OmrRegistrationResult(
        failureCode: OmrFailureCode.fiducialsNotFound,
        candidateCount: candidates.length,
        fiducials: const [],
        score: 0,
      );
    }

    List<_MarkerCandidate>? best;
    var bestScore = 0.0;
    for (final tl in quadrants[0]) {
      for (final tr in quadrants[1]) {
        for (final br in quadrants[2]) {
          for (final bl in quadrants[3]) {
            final set = [tl, tr, br, bl];
            final geometry = _geometryScore(
              set,
              work.width,
              work.height,
              layout,
            );
            if (geometry <= 0) continue;
            final candidateScore =
                set
                    .map((candidate) => candidate.score)
                    .reduce((a, b) => a + b) /
                4;
            final score = geometry * .62 + candidateScore * .38;
            if (score > bestScore) {
              bestScore = score;
              best = set;
            }
          }
        }
      }
    }

    if (best == null || bestScore < .48) {
      return OmrRegistrationResult(
        failureCode: OmrFailureCode.invalidFiducialGeometry,
        candidateCount: candidates.length,
        fiducials: const [],
        score: bestScore,
      );
    }

    final inverseScale = 1 / scale;
    return OmrRegistrationResult(
      failureCode: OmrFailureCode.none,
      candidateCount: candidates.length,
      fiducials: best
          .map(
            (candidate) => OmrPoint(
              candidate.center.x * inverseScale,
              candidate.center.y * inverseScale,
            ),
          )
          .toList(growable: false),
      score: bestScore.clamp(0, 1).toDouble(),
    );
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

    final visited = Uint8List(width * height);
    final queue = <int>[];
    final candidates = <_MarkerCandidate>[];
    final minArea = math.max(24, (width * height * .00005).round());
    final maxArea = math.max(minArea + 1, (width * height * .025).round());

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final start = y * width + x;
        if (mask[start] == 0 || visited[start] != 0) continue;
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
              if (mask[next] == 0 || visited[next] != 0) continue;
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
    if (top < width * .25 || bottom < width * .25) return 0;
    if (left < height * .25 || right < height * .25) return 0;
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
    if (areaFraction < .10) return 0;

    final observedAspect = ((top + bottom) / 2) / ((left + right) / 2);
    final expectedAspect = layout.boxW / layout.boxH;
    final aspectRatio = observedAspect / expectedAspect;
    final aspectScore = math.exp(-.55 * math.log(aspectRatio).abs());
    final areaScore = (areaFraction / .45).clamp(0.0, 1.0);
    return (horizontalConsistency * .22 +
            verticalConsistency * .22 +
            sizeConsistency * .20 +
            aspectScore * .20 +
            areaScore * .16)
        .clamp(0, 1)
        .toDouble();
  }
}
