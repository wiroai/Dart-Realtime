import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/app/theme/app_text_styles.dart';

/// Call duration in tabular figures so the digits do not shift width as
/// they tick.
class ConversationTimer extends StatelessWidget {
  const ConversationTimer({
    required this.elapsed,
    this.large = false,
    super.key,
  });

  final Duration elapsed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final base = large
        ? AppTextStyles.metricMedium
        : AppTextStyles.mono.copyWith(fontWeight: FontWeight.w600);
    return Text(
      '$minutes:$seconds',
      style: base.copyWith(
        color: context.colorScheme.onSurface,
        fontFamilyFallback: AppTextStyles.monoFallback,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
