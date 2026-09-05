import 'package:flutter/material.dart';

/// Lightweight playback for the generated Bayaz operation artwork.
///
/// The shipping animations are encoded as animated WebP files so Flutter's image
/// codec owns frame timing instead of a Dart timer swapping individual widgets.
/// The original PNG frames remain as editable source assets and provide a static
/// final frame when the platform asks us to reduce motion.
class BayazFrameAnimation extends StatelessWidget {
  const BayazFrameAnimation({
    super.key,
    required this.name,
    this.size = 160,
    this.fps = 12,
    this.loop = true,
  });

  final String name;
  final double size;

  /// Retained for source compatibility with the old frame player. Shipping WebP
  /// files are encoded at 12 fps.
  final int fps;

  /// Retained for source compatibility. All current operation-art call sites are
  /// looping animations and the bundled WebP files loop continuously.
  final bool loop;

  String get _animatedAsset => 'assets/ui/animations/$name.webp';
  String get _reducedMotionAsset => 'assets/ui/animations/frames/$name/12.png';

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        reduceMotion ? _reducedMotionAsset : _animatedAsset,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }
}
