import 'package:flutter/material.dart';

/// Type scale from the wiro.ai design tokens.
///
/// Styles carry no colour so a caller can place the same size on light,
/// warm, or inverted surfaces without a competing default.
///
/// The site uses weights 550 and 650, which Flutter's [FontWeight] does
/// not expose; both land on [FontWeight.w600]. Letter spacing is the
/// token's `em` value resolved against the style's own font size.
abstract final class AppTextStyles {
  /// Small tracked-out label that sits above a section heading.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.63,
    height: 1.2,
  );

  static const TextStyle micro = TextStyle(fontSize: 11);

  static const TextStyle caption = TextStyle(fontSize: 12);

  static const TextStyle meta = TextStyle(fontSize: 12.5, height: 1.5);

  static const TextStyle buttonSmall = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle row = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  static const TextStyle pageSubtitle = TextStyle(
    fontSize: 13.5,
    height: 1.45,
  );

  static const TextStyle title = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle metricSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.63,
    height: 1.1,
  );

  static const TextStyle metricMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.77,
    height: 1.1,
  );

  static const TextStyle metricLarge = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.05,
    height: 1.1,
  );

  /// Tabular figures for timers and protocol output.
  ///
  /// The fonts are not bundled, so this resolves to whichever monospace
  /// family the platform provides.
  static const List<String> monoFallback = [
    'JetBrains Mono',
    'SF Mono',
    'Menlo',
    'Roboto Mono',
    'monospace',
  ];

  static const TextStyle mono = TextStyle(
    fontSize: 12.5,
    height: 1.45,
    fontFamilyFallback: monoFallback,
  );
}
