import 'dart:async';

import 'package:flutter/material.dart';

import 'grading_screen.dart';
import 'image_pick_recovery.dart';

class ImagePickRecoveryGate extends StatefulWidget {
  const ImagePickRecoveryGate({
    super.key,
    required this.child,
    this.service,
  });

  final Widget child;
  final ImagePickRecoveryService? service;

  @override
  State<ImagePickRecoveryGate> createState() => _ImagePickRecoveryGateState();
}

class _ImagePickRecoveryGateState extends State<ImagePickRecoveryGate> {
  late final ImagePickRecoveryService _service;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ImagePickRecoveryService();
    unawaited(_recover());
  }

  Future<void> _recover() async {
    try {
      final recovered = await _service.recover();
      if (!mounted || recovered == null || _opened) return;
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GradingScreen(
            test: recovered.test,
            initialImagePath: recovered.imagePath,
            recoveryStore: _service.store,
          ),
        ));
      });
    } catch (_) {
      // Startup remains usable. The pending record is retained for a later retry.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
