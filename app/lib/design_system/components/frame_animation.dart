import 'dart:async';

import 'package:flutter/material.dart';

/// Lightweight frame animation for the generated Rahbar asset sheets.
///
/// Uses the individually exported frames rather than decoding a sprite sheet at
/// runtime. This keeps the implementation dependency-free and lets Flutter cache
/// each frame normally.
class RahbarFrameAnimation extends StatefulWidget {
  const RahbarFrameAnimation({
    super.key,
    required this.name,
    this.size = 160,
    this.fps = 8,
    this.loop = false,
  });

  final String name;
  final double size;
  final int fps;
  final bool loop;

  @override
  State<RahbarFrameAnimation> createState() => _RahbarFrameAnimationState();
}

class _RahbarFrameAnimationState extends State<RahbarFrameAnimation> {
  int _frame = 1;
  Timer? _timer;

  String _asset(int frame) =>
      'assets/ui/animations/frames/${widget.name}/${frame.toString().padLeft(2, '0')}.png';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (var i = 1; i <= 12; i++) {
      precacheImage(AssetImage(_asset(i)), context);
    }
    _start();
  }

  void _start() {
    _timer?.cancel();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _frame = 12;
      return;
    }
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / widget.fps).round()),
      (timer) {
        if (!mounted) return;
        if (_frame >= 12) {
          if (widget.loop) {
            setState(() => _frame = 1);
          } else {
            timer.cancel();
          }
        } else {
          setState(() => _frame++);
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant RahbarFrameAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name ||
        oldWidget.loop != widget.loop ||
        oldWidget.fps != widget.fps) {
      _frame = 1;
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 90),
        child: Image.asset(
          _asset(_frame),
          key: ValueKey(_frame),
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
