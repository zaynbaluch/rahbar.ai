import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'bayaz_card.dart';
import 'frame_animation.dart';

/// Reusable retention panel for operations that genuinely take long enough to
/// need explanation. Short database and navigation loads should keep using a
/// normal progress indicator instead.
class LongOperationPanel extends StatefulWidget {
  const LongOperationPanel({
    super.key,
    required this.primaryStatus,
    required this.messages,
    this.animationNames = const [
      'scanning_answers',
      'test_ready',
      'lesson_saved',
    ],
    this.rotateEvery = const Duration(seconds: 10),
    this.progress,
    this.progressLabel,
  });

  final String primaryStatus;
  final List<String> messages;
  final List<String> animationNames;
  final Duration rotateEvery;
  final double? progress;
  final String? progressLabel;

  @override
  State<LongOperationPanel> createState() => _LongOperationPanelState();
}

class _LongOperationPanelState extends State<LongOperationPanel> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant LongOperationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages != widget.messages ||
        oldWidget.animationNames != widget.animationNames ||
        oldWidget.rotateEvery != widget.rotateEvery) {
      _index = 0;
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    if (widget.messages.length <= 1 && widget.animationNames.length <= 1) {
      return;
    }
    _timer = Timer.periodic(widget.rotateEvery, (_) {
      if (!mounted) return;
      setState(() => _index++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.messages.isEmpty
        ? widget.primaryStatus
        : widget.messages[_index % widget.messages.length];
    final animation = widget.animationNames.isEmpty
        ? 'scanning_answers'
        : widget.animationNames[_index % widget.animationNames.length];
    return BayazCard(
      color: AppColors.softBlue,
      borderColor: const Color(0xFFC9D6FF),
      child: Column(
        children: [
          BayazFrameAnimation(name: animation, size: 154, loop: true),
          Text(
            widget.primaryStatus,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              message,
              key: ValueKey(message),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (widget.progressLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.progressLabel!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: widget.progress),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Please keep this screen open.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
