import 'package:flutter/material.dart';

/// Elevation from the wiro.ai design tokens.
///
/// The site keeps content cards flat and reserves shadow for surfaces
/// that float above the page, so these are used sparingly.
abstract final class AppShadows {
  static const List<BoxShadow> small = [
    BoxShadow(
      color: Color(0x0D16140F),
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x1416140F),
      offset: Offset(0, 14),
      blurRadius: 34,
    ),
  ];
}
