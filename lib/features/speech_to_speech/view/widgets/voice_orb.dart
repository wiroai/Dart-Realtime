import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/media_query_extension.dart';
import 'package:wiro_realtime/app/layout/project_duration.dart';
import 'package:wiro_realtime/app/theme/app_colors.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb_pulse.dart';

enum VoiceOrbMode { idle, connecting, listening, paused, ended, failed }

/// The screen's focal point and, before a session starts, its only
/// control: one shape that carries the whole session state and is itself
/// the button that begins it.
///
/// Idle, it has no label to explain itself, so it explains itself by
/// moving: rings travel outward and the shape swells and settles, which is
/// how a thing asks to be pressed.
///
/// During connection, the pulse starts immediately to show that the tap
/// was accepted. Live, it reports that the microphone is open, not how
/// loud the room is.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    required this.mode,
    required this.size,
    this.progress,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final VoiceOrbMode mode;
  final double size;

  /// Connection progress from 0 to 1. The ring is hidden when null.
  final double? progress;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// One size for every stage, so starting or ending a conversation never
  /// resizes the shape the eye is fixed on.
  ///
  /// Read from the viewport rather than a `LayoutBuilder`: the panels sit
  /// inside slivers that measure their child's intrinsic height, and a
  /// `LayoutBuilder` cannot answer that.
  static double sizeFor(BuildContext context) {
    return (context.height * 0.2).clamp(120.0, 190.0);
  }

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ProjectDuration.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _VoiceOrbStyle.of(widget.mode);
    final orb = SizedBox.square(
      dimension: widget.size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: widget.progress ?? 0),
        duration: ProjectDuration.stageSwap,
        curve: Curves.easeOut,
        builder: (context, progress, _) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Transform.scale(
            scale: style.throbs ? 0.96 + 0.04 * _wave : 1,
            child: CustomPaint(
              painter: VoiceOrbPulsePainter(
                pulse: _controller.value,
                ringCount: style.ringCount,
                ringColor: style.ringColor,
                coreColor: style.coreColor,
                borderColor: style.borderColor,
                progress: widget.progress == null ? null : progress,
                progressStart: widget.mode == VoiceOrbMode.connecting
                    ? _controller.value
                    : 0,
                progressColor: style.progressColor,
                trackColor: AppColors.borderMedium,
              ),
              child: Center(
                child: Opacity(
                  opacity: style.breathes ? 0.45 + 0.55 * _wave : 1,
                  child: Icon(
                    style.icon,
                    size: widget.size * 0.24,
                    color: style.iconColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final onTap = widget.onTap;
    return Semantics(
      button: onTap != null,
      label: widget.semanticLabel,
      child: onTap == null
          ? ExcludeSemantics(child: orb)
          : Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: ExcludeSemantics(child: orb),
              ),
            ),
    );
  }

  /// A single rise and fall over one cycle, so whatever it drives eases
  /// both ways instead of snapping back at the loop point.
  double get _wave {
    if (!_controller.isAnimating) {
      return 1;
    }
    return 1 - (_controller.value * 2 - 1).abs();
  }

  /// Keeps the ticker off whenever the current mode has nothing to
  /// animate, so a finished or failed screen costs no frames.
  void _syncAnimation() {
    final style = _VoiceOrbStyle.of(widget.mode);
    final animate =
        (style.ringCount > 0 || style.breathes || style.throbs) &&
        !MediaQuery.disableAnimationsOf(context);
    _controller.duration = style.period;
    if (animate == _controller.isAnimating) {
      return;
    }
    if (animate) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }
}

class _VoiceOrbStyle {
  const _VoiceOrbStyle({
    required this.ringCount,
    required this.ringColor,
    required this.coreColor,
    required this.borderColor,
    required this.progressColor,
    required this.icon,
    required this.iconColor,
    required this.breathes,
    required this.throbs,
    required this.period,
  });

  factory _VoiceOrbStyle.of(VoiceOrbMode mode) {
    return switch (mode) {
      // The only affordance left on the setup screen, so it moves: rings
      // outward, and the shape itself swelling under them.
      VoiceOrbMode.idle => const _VoiceOrbStyle(
        ringCount: 2,
        ringColor: AppColors.inkMuted,
        coreColor: AppColors.ink,
        borderColor: AppColors.ink,
        progressColor: AppColors.green,
        icon: Icons.mic_rounded,
        iconColor: AppColors.onDark,
        breathes: false,
        throbs: true,
        period: ProjectDuration.invite,
      ),
      VoiceOrbMode.connecting => const _VoiceOrbStyle(
        ringCount: 0,
        ringColor: AppColors.green,
        coreColor: AppColors.ink,
        borderColor: AppColors.ink,
        progressColor: AppColors.greenBright,
        icon: Icons.mic_rounded,
        iconColor: AppColors.onDark,
        breathes: true,
        throbs: false,
        period: ProjectDuration.pulse,
      ),
      VoiceOrbMode.listening => const _VoiceOrbStyle(
        ringCount: 3,
        ringColor: AppColors.greenBright,
        coreColor: AppColors.ink,
        borderColor: AppColors.ink,
        progressColor: AppColors.greenBright,
        icon: Icons.mic_rounded,
        iconColor: AppColors.onDark,
        breathes: false,
        throbs: false,
        period: ProjectDuration.pulse,
      ),
      VoiceOrbMode.paused => const _VoiceOrbStyle(
        ringCount: 0,
        ringColor: AppColors.border,
        coreColor: AppColors.backgroundStone,
        borderColor: AppColors.borderMedium,
        progressColor: AppColors.green,
        icon: Icons.play_arrow_rounded,
        iconColor: AppColors.inkMuted,
        breathes: false,
        throbs: false,
        period: ProjectDuration.pulse,
      ),
      VoiceOrbMode.ended => const _VoiceOrbStyle(
        ringCount: 0,
        ringColor: AppColors.border,
        coreColor: AppColors.greenSubtle,
        borderColor: AppColors.greenBorder,
        progressColor: AppColors.green,
        icon: Icons.check_rounded,
        iconColor: AppColors.greenText,
        breathes: false,
        throbs: false,
        period: ProjectDuration.pulse,
      ),
      VoiceOrbMode.failed => const _VoiceOrbStyle(
        ringCount: 0,
        ringColor: AppColors.border,
        coreColor: AppColors.dangerSubtle,
        borderColor: AppColors.dangerBorder,
        progressColor: AppColors.danger,
        icon: Icons.priority_high_rounded,
        iconColor: AppColors.dangerText,
        breathes: false,
        throbs: false,
        period: ProjectDuration.pulse,
      ),
    };
  }

  final int ringCount;
  final Color ringColor;
  final Color coreColor;
  final Color borderColor;
  final Color progressColor;
  final IconData icon;
  final Color iconColor;

  /// Fades the icon in and out: the connecting orb is working, not waiting.
  final bool breathes;

  /// Scales the whole shape: the idle orb is asking to be pressed.
  final bool throbs;
  final Duration period;
}
