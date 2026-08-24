import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws the orb: a filled core, outward pulse rings while it is
/// listening, and a progress ring that closes as the session connects.
///
/// The closing ring is the whole connection story in one shape — when the
/// circle completes, the conversation is live.
class VoiceOrbPulsePainter extends CustomPainter {
  const VoiceOrbPulsePainter({
    required this.pulse,
    required this.ringCount,
    required this.ringColor,
    required this.coreColor,
    required this.borderColor,
    required this.progress,
    required this.progressStart,
    required this.progressColor,
    required this.trackColor,
  });

  /// One shared cycle for the pulse rings, offset per ring so the wave is
  /// continuous rather than restarting all at once.
  final double pulse;
  final int ringCount;
  final Color ringColor;
  final Color coreColor;
  final Color borderColor;

  /// How much of the connection is done, or `null` when nothing is
  /// connecting.
  final double? progress;

  /// Rotation of the connection arc from 0 to 1.
  final double progressStart;
  final Color progressColor;
  final Color trackColor;

  static const double _coreFraction = 0.74;
  static const double _progressWidth = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.shortestSide / 2;
    final coreRadius = outerRadius * _coreFraction;

    for (var index = 0; index < ringCount; index++) {
      final travel = (pulse + index / ringCount) % 1;
      final radius = coreRadius + (outerRadius - coreRadius) * travel;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ringColor.withValues(alpha: (1 - travel) * 0.45),
      );
    }

    canvas
      ..drawCircle(center, coreRadius, Paint()..color = coreColor)
      ..drawCircle(
        center,
        coreRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = borderColor,
      );

    final sweep = progress;
    if (sweep == null) {
      return;
    }
    final trackRadius = outerRadius - _progressWidth / 2;
    final bounds = Rect.fromCircle(center: center, radius: trackRadius);
    canvas
      ..drawCircle(
        center,
        trackRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _progressWidth
          ..color = trackColor,
      )
      ..drawArc(
        bounds,
        -math.pi / 2 + progressStart * 2 * math.pi,
        sweep.clamp(0.0, 1.0) * 2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _progressWidth
          ..strokeCap = StrokeCap.round
          ..color = progressColor,
      );
  }

  @override
  bool shouldRepaint(VoiceOrbPulsePainter oldDelegate) {
    return oldDelegate.pulse != pulse ||
        oldDelegate.ringCount != ringCount ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.coreColor != coreColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.progress != progress ||
        oldDelegate.progressStart != progressStart ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor;
  }
}
