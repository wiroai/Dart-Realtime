import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';

/// The "I can hear you" signal: a row of bars moving while the
/// microphone streams.
///
/// The session never publishes microphone levels, so the motion is
/// layered sine waves rather than real amplitude — steady, symmetric,
/// and calm, the way recorder apps animate. What matters is that it
/// moves while the app listens and only then; reduced motion parks the
/// bars at mid-height.
class TranscriptionWave extends StatefulWidget {
  const TranscriptionWave({super.key});

  @override
  State<TranscriptionWave> createState() => _TranscriptionWaveState();
}

class _TranscriptionWaveState extends State<TranscriptionWave>
    with SingleTickerProviderStateMixin {
  static const int _barCount = 21;
  static const double _barWidth = 3;
  static const double _barGap = 3;
  static const double _maxBarHeight = 26;
  static const double _minBarHeight = 4;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _heightFor(int index, double phase) {
    // A symmetric envelope keeps the tall bars in the middle; two sine
    // layers at different speeds keep the motion organic without jitter.
    final envelope = math.sin(math.pi * index / (_barCount - 1));
    final swing =
        0.6 * math.sin(2 * math.pi * phase + index * 0.7) +
        0.4 * math.sin(4 * math.pi * phase - index * 0.35);
    final level = envelope * (0.5 + 0.5 * swing).clamp(0.0, 1.0);
    return _minBarHeight + (_maxBarHeight - _minBarHeight) * level;
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value;
        final still = !_controller.isAnimating;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _barCount; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _barGap / 2,
                ),
                child: SizedBox(
                  width: _barWidth,
                  height: still
                      ? _minBarHeight +
                            (_maxBarHeight - _minBarHeight) *
                                math.sin(math.pi * i / (_barCount - 1))
                      : _heightFor(i, phase),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(
                        _barWidth / 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
