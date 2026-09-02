import 'package:image/image.dart' as img;

class OmrImageQualityReport {
  const OmrImageQualityReport({
    required this.width,
    required this.height,
    required this.meanLuminance,
    required this.darkClipFraction,
    required this.lightClipFraction,
    required this.blurVariance,
    required this.warnings,
  });

  final int width;
  final int height;
  final double meanLuminance;
  final double darkClipFraction;
  final double lightClipFraction;
  final double blurVariance;
  final List<String> warnings;

  bool get usableDimensions => width >= 240 && height >= 240;
}

abstract final class OmrImageQuality {
  static OmrImageQualityReport measure(img.Image gray) {
    final width = gray.width;
    final height = gray.height;
    if (width == 0 || height == 0) {
      return OmrImageQualityReport(
        width: width,
        height: height,
        meanLuminance: 0,
        darkClipFraction: 1,
        lightClipFraction: 0,
        blurVariance: 0,
        warnings: const ['image has no usable pixels'],
      );
    }

    double luminanceSum = 0;
    var dark = 0;
    var light = 0;
    var sampled = 0;
    final pixelStep = (width * height > 1600000) ? 2 : 1;
    for (var y = 0; y < height; y += pixelStep) {
      for (var x = 0; x < width; x += pixelStep) {
        final value = gray.getPixel(x, y).luminance.toDouble();
        luminanceSum += value;
        if (value <= 18) dark++;
        if (value >= 248) light++;
        sampled++;
      }
    }
    final mean = sampled == 0 ? 0.0 : luminanceSum / sampled;

    double lapSum = 0;
    double lapSqSum = 0;
    var lapCount = 0;
    final lapStep = (width * height > 900000) ? 3 : 2;
    for (var y = 1; y < height - 1; y += lapStep) {
      for (var x = 1; x < width - 1; x += lapStep) {
        final center = gray.getPixel(x, y).luminance.toDouble();
        final lap =
            gray.getPixel(x - 1, y).luminance.toDouble() +
            gray.getPixel(x + 1, y).luminance.toDouble() +
            gray.getPixel(x, y - 1).luminance.toDouble() +
            gray.getPixel(x, y + 1).luminance.toDouble() -
            4 * center;
        lapSum += lap;
        lapSqSum += lap * lap;
        lapCount++;
      }
    }
    final lapMean = lapCount == 0 ? 0.0 : lapSum / lapCount;
    final blurVariance = lapCount == 0
        ? 0.0
        : (lapSqSum / lapCount) - lapMean * lapMean;

    final darkFraction = sampled == 0 ? 0.0 : dark / sampled;
    final lightFraction = sampled == 0 ? 0.0 : light / sampled;
    final warnings = <String>[];
    if (width < 240 || height < 240) {
      warnings.add('image resolution is too small');
    }
    if (mean < 70) {
      warnings.add('image is very dark');
    }
    if (mean > 246) {
      warnings.add('image is very bright');
    }
    if (darkFraction > .45) {
      warnings.add('large parts of the image are clipped dark');
    }
    if (lightFraction > .97) {
      warnings.add('large parts of the image are clipped light');
    }
    if (blurVariance < 18 && width >= 240 && height >= 240) {
      warnings.add('image may be out of focus');
    }

    return OmrImageQualityReport(
      width: width,
      height: height,
      meanLuminance: mean,
      darkClipFraction: darkFraction.toDouble(),
      lightClipFraction: lightFraction.toDouble(),
      blurVariance: blurVariance.clamp(0, double.infinity).toDouble(),
      warnings: warnings,
    );
  }
}
