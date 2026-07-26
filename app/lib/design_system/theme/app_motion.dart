import 'package:flutter/animation.dart';

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 240);
  static const emphasis = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
}
