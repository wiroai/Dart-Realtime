import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Draws every layer of the orb: a blurred halo that swells with the live
/// voice level, outward pulse rings, the filled core, waveform bars while
/// someone is audibly speaking, the progress ring that closes as the
/// session connects, and the two rings that only exist mid-transition —
/// the shockwave a stage change sends out and the connect ring letting go.
class VoiceOrbPainter extends CustomPainter {
  const VoiceOrbPainter({
    required this.pulse,
    required this.ringCount,
    required this.ringOpacity,
    required this.ringColor,
    required this.coreColor,
    required this.borderColor,
    required this.haloColor,
    required this.haloStrength,
    required this.barLevels,
    required this.barColor,
    required this.barsOpacity,
    required this.progress,
    required this.progressColor,
    required this.trackColor,
    required this.transition,
    required this.transitionStrength,
    required this.releasedProgress,
  });

  final double pulse;
  final int ringCount;
  final double ringOpacity;
  final Color ringColor;
  final Color coreColor;
  final Color borderColor;
  final Color haloColor;
  final double haloStrength;
  final List<double> barLevels;
  final Color barColor;
  final double barsOpacity;
  final double? progress;
  final Color progressColor;
  final Color trackColor;

  /// How far the current stage change has run, 0 to 1. Drives the two
  /// transition-only rings, which are drawn as one shape leaving rather
  /// than one shape fading, so a stage change has a direction.
  final double transition;

  /// Zero for the state changes that happen several times a second — the
  /// live orb passing the floor between two speakers — and one for the
  /// handful a person actually experiences as a step.
  final double transitionStrength;

  /// The connect ring's last value, kept only while it flies outward, so
  /// the ring is seen letting go instead of blinking out.
  final double? releasedProgress;

  static const double _coreFraction = 0.74;
  static const double _progressWidth = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.shortestSide / 2;
    final coreRadius = outerRadius * _coreFraction;

    _paintHalo(canvas, center, coreRadius, outerRadius);
    _paintRings(canvas, center, coreRadius, outerRadius);
    _paintCore(canvas, center, coreRadius);
    _paintBars(canvas, center, coreRadius);
    _paintProgress(canvas, center, outerRadius);
    _paintReleasedProgress(canvas, center, outerRadius);
    _paintShockwave(canvas, center, coreRadius, outerRadius);
  }

  void _paintHalo(
    Canvas canvas,
    Offset center,
    double coreRadius,
    double outerRadius,
  ) {
    if (haloStrength <= 0.01) {
      return;
    }
    final radius =
        coreRadius +
        (outerRadius - coreRadius) * 0.35 +
        coreRadius * 0.2 * haloStrength;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = haloColor.withValues(
          alpha: (0.1 + 0.32 * haloStrength).clamp(0.0, 0.42),
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          outerRadius * 0.18,
        ),
    );
  }

  void _paintRings(
    Canvas canvas,
    Offset center,
    double coreRadius,
    double outerRadius,
  ) {
    if (ringCount == 0 || ringOpacity <= 0.01) {
      return;
    }
    for (var index = 0; index < ringCount; index++) {
      final travel = (pulse + index / ringCount) % 1;
      final radius = coreRadius + (outerRadius - coreRadius) * travel;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ringColor.withValues(
            alpha: (1 - travel) * 0.45 * ringOpacity,
          ),
      );
    }
  }

  void _paintCore(Canvas canvas, Offset center, double coreRadius) {
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
  }

  void _paintBars(Canvas canvas, Offset center, double coreRadius) {
    if (barLevels.isEmpty || barsOpacity <= 0.01) {
      return;
    }
    final barWidth = coreRadius * 0.15;
    final gap = coreRadius * 0.15;
    final span = barLevels.length * barWidth + (barLevels.length - 1) * gap;
    final maxHeight = coreRadius * 1.1;
    final paint = Paint()
      ..color = barColor.withValues(alpha: barsOpacity.clamp(0.0, 1.0))
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;
    var x = center.dx - span / 2 + barWidth / 2;
    for (final level in barLevels) {
      final halfHeight = math.max(
        barWidth * 0.15,
        maxHeight * level.clamp(0.0, 1.0) / 2,
      );
      canvas.drawLine(
        Offset(x, center.dy - halfHeight),
        Offset(x, center.dy + halfHeight),
        paint,
      );
      x += barWidth + gap;
    }
  }

  void _paintProgress(Canvas canvas, Offset center, double outerRadius) {
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
          // The track fades in behind the first sweep rather than being
          // there before it, so the ring arrives as one gesture.
          ..color = trackColor.withValues(
            alpha: trackColor.a * (sweep / 0.15).clamp(0.0, 1.0),
          ),
      )
      ..drawArc(
        bounds,
        -math.pi / 2,
        sweep.clamp(0.0, 1.0) * 2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _progressWidth
          ..strokeCap = StrokeCap.round
          ..color = progressColor,
      );
  }

  /// The ring the connection has finished with: it widens past the orb and
  /// thins out, so the moment the conversation goes live reads as a held
  /// breath being let out.
  void _paintReleasedProgress(
    Canvas canvas,
    Offset center,
    double outerRadius,
  ) {
    final sweep = releasedProgress;
    if (sweep == null || transition >= 1) {
      return;
    }
    // The ring holds its place for a beat before it goes, so the closing
    // of the arc is read first and the release second. Fading is linear
    // against that, which is what keeps it visible while it holds.
    final travel = Curves.easeInOutCubic.transform(transition);
    final fade = 1 - transition;
    final radius =
        outerRadius - _progressWidth / 2 + outerRadius * 0.32 * travel;
    canvas
      ..drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _progressWidth * (1 - travel * 0.35)
          ..color = trackColor.withValues(alpha: trackColor.a * fade),
      )
      ..drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        // Closing the last of the arc as it leaves finishes the thought
        // the ring was in the middle of.
        (sweep + (1 - sweep) * travel).clamp(0.0, 1.0) * 2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _progressWidth * (1 - travel * 0.35)
          ..strokeCap = StrokeCap.round
          ..color = progressColor.withValues(alpha: fade),
      );
  }

  /// One ring thrown outward per stage change, fading as it goes. It is
  /// what makes a tap feel answered and a connection feel completed
  /// rather than swapped.
  void _paintShockwave(
    Canvas canvas,
    Offset center,
    double coreRadius,
    double outerRadius,
  ) {
    if (transitionStrength <= 0.01 || transition >= 1) {
      return;
    }
    final travel = Curves.easeOut.transform(transition);
    canvas.drawCircle(
      center,
      coreRadius + (outerRadius - coreRadius + outerRadius * 0.4) * travel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - travel)
        ..color = ringColor.withValues(
          alpha: (1 - travel) * 0.55 * transitionStrength,
        ),
    );
  }

  @override
  bool shouldRepaint(VoiceOrbPainter oldDelegate) {
    return oldDelegate.pulse != pulse ||
        oldDelegate.ringCount != ringCount ||
        oldDelegate.ringOpacity != ringOpacity ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.coreColor != coreColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.haloColor != haloColor ||
        oldDelegate.haloStrength != haloStrength ||
        !listEquals(oldDelegate.barLevels, barLevels) ||
        oldDelegate.barColor != barColor ||
        oldDelegate.barsOpacity != barsOpacity ||
        oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.transition != transition ||
        oldDelegate.transitionStrength != transitionStrength ||
        oldDelegate.releasedProgress != releasedProgress;
  }
}
