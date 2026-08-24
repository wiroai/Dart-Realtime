import 'package:flutter/material.dart';

/// Light-mode palette from the wiro.ai design tokens.
///
/// Translucent tokens keep the site's percentage alpha: `0x14` is 8%,
/// `0x1A` is 10%, `0x3D` is 24%, `0xDB` is 86%.
abstract final class AppColors {
  static const Color background = Color(0xFFF9F8F5);
  static const Color backgroundHover = Color(0xFFF4F1EA);
  static const Color backgroundWarm = Color(0xFFF2EFE8);
  static const Color backgroundStone = Color(0xFFEDEAE2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceFrost = Color(0xDBFFFFFF);

  static const Color ink = Color(0xFF16140F);
  static const Color inkHover = Color(0xFF2A2820);
  static const Color inkSecondary = Color(0xFF3D3A33);
  static const Color inkMuted = Color(0xFF706C62);
  static const Color inkDisabled = Color(0xFFA8A49A);

  static const Color green = Color(0xFF2E7D52);
  static const Color greenMid = Color(0xFF3A9463);
  static const Color greenStrong = Color(0xFF3F9E68);
  static const Color greenBright = Color(0xFF4CAF76);
  static const Color greenText = Color(0xFF1E5C38);
  static const Color greenContainer = Color(0xFFEAF2ED);
  static const Color greenSubtle = Color(0x142E7D52);
  static const Color greenBorder = Color(0x3D2E7D52);

  static const Color blue = Color(0xFF3B64B4);
  static const Color amber = Color(0xFFC99A40);
  static const Color amberText = Color(0xFF7A5010);
  static const Color amberSubtle = Color(0x1AC99A40);
  static const Color danger = Color(0xFFC05050);
  static const Color dangerText = Color(0xFFB3471E);
  static const Color dangerContainer = Color(0xFFF5ECE7);
  static const Color dangerSubtle = Color(0x14B3471E);
  static const Color dangerBorder = Color(0x3DB3471E);

  static const Color border = Color(0x1216140F);
  static const Color borderMedium = Color(0x1C16140F);
  static const Color borderStrong = Color(0x3316140F);

  static const Color darkSurface = Color(0xFF1E1C16);
  static const Color onDark = Color(0xFFF9F8F5);
}
