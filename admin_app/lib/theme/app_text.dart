import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

abstract final class AppText {
  static const display = TextStyle(fontSize: 28, fontWeight: FontWeight.w800);
  static const title = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  static const section = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);
  static const body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400);
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
  static const numeric = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w700,
  );
}
