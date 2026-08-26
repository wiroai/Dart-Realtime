import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/media_query_extension.dart';
import 'package:wiro_realtime/app/layout/project_duration.dart';
import 'package:wiro_realtime/app/theme/app_colors.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_voice_activity.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb_painter.dart';

/// Every situation the orb can report, each with its own icon, colours and
/// motion so the state is readable at a glance.
enum VoiceOrbMode {
  /// Waiting for the first tap: a dark orb that swells to invite it.
  idle,

  /// Getting ready: the dark orb wakes into the same bars that will carry
  /// the live conversation, and a ring around it closes as each connect
  /// step lands. No spinner: the shape that is about to listen is the
  /// thing reporting how close it is.
  connecting,

  /// Live and quiet: gently bobbing bars show an open ear waiting for a
  /// voice, and they stir the moment any sound arrives.
  listening,

  /// The user is audibly talking: bars dance to the microphone level.
  userSpeaking,

  /// The assistant is audibly talking: the orb turns green and pulses
  /// with the voice, the way ChatGPT's voice mode does.
  speaking,

  /// Capture is muted; a tap resumes it.
  paused,
}

/// The screen's focal point and, before a session starts, its only control:
/// one shape that carries the whole session state and is itself the button
/// that begins it.
///
/// Live, it no longer reports only that the microphone is open. Fed by
/// [ConversationVoiceActivity] it shows who owns the moment: a calm dark
/// orb while it listens, reactive bars and a glowing halo while the user
/// talks, and a green orb pulsing with the assistant's own audio while the
/// assistant answers.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    required this.mode,
    required this.size,
    this.activity,
    this.progress,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final VoiceOrbMode mode;
  final double size;

  /// Continuous voice levels polled once per frame; null outside live
  /// stages, where the orb has no voice to react to.
  final ConversationVoiceActivity? activity;

  /// Connection progress from 0 to 1. The ring is hidden when null.
  final double? progress;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// One size for every stage, so starting or ending a conversation never
  /// resizes the shape the eye is fixed on.
  ///
  /// Measured against the phone rather than the box the orb is handed,
  /// because the clamp is about how big a circle a hand wants to tap, and
  /// that does not change when a line of text appears under it.
  static double sizeFor(BuildContext context) {
    return (context.height * 0.2).clamp(120.0, 190.0);
  }

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with TickerProviderStateMixin {
  /// Long enough for a stage change to be watched rather than noticed
  /// afterwards, short enough that a tap still feels answered at once.
  static const Duration _modeBlend = Duration(milliseconds: 460);

  /// How far the orb sinks under a finger. The press is the first half of
  /// starting a conversation, so it answers before any state arrives.
  static const double _pressScale = 0.94;

  /// Per-bar phase offsets and weights: the wobble keeps the five bars out
  /// of step with each other so the cluster moves like a voice rather than
  /// a metronome, and the weights bow the silhouette toward the centre.
  static const List<double> _barSeeds = [0.0, 2.1, 4.2, 1.1, 3.4];
  static const List<double> _barWeights = [0.55, 0.8, 1, 0.8, 0.55];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ProjectDuration.pulse,
  );

  /// Crossfades the previous mode's look into the next one, so the orb
  /// morphs between states instead of snapping.
  late final AnimationController _blendController = AnimationController(
    vsync: this,
    duration: _modeBlend,
    value: 1,
  );

  late _VoiceOrbStyle _target = _VoiceOrbStyle.of(widget.mode);
  _VoiceOrbStyle? _blendFrom;

  /// Full for a change the user lives through — a tap answered, a
  /// connection completed — and zero for the live orb handing the floor
  /// back and forth, which happens several times a sentence.
  double _transitionStrength = 0;

  /// The connect ring's last value, held for one blend so it can be seen
  /// leaving.
  double? _releasedProgress;
  double _level = 0;
  double _barPhase = 0;
  bool _pressed = false;
  DateTime _lastTick = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    final released = widget.progress == null && oldWidget.progress != null;
    if (widget.progress != null) {
      _releasedProgress = null;
    } else if (released) {
      _releasedProgress = oldWidget.progress;
    }
    if (oldWidget.mode != widget.mode) {
      // The ring rides the one blend that let it go and no other. Every
      // later stage change rewinds that blend, and a ring left behind
      // would be redrawn against each of them — around the orb of a
      // conversation in progress, several times a sentence, as the floor
      // passes between the two speakers.
      if (!released) {
        _releasedProgress = null;
      }
      _blendFrom = _displayStyle;
      _target = _VoiceOrbStyle.of(widget.mode);
      _transitionStrength = _stageOf(oldWidget.mode) == _stageOf(widget.mode)
          ? 0
          : 1;
      _blendController.forward(from: 0);
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _blendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orb = AnimatedScale(
      scale: _pressed ? _pressScale : 1,
      duration: ProjectDuration.transition,
      curve: Curves.easeOut,
      child: SizedBox.square(
        dimension: widget.size,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: widget.progress ?? 0),
          duration: ProjectDuration.stageSwap,
          curve: Curves.easeOut,
          builder: (context, progress, _) => AnimatedBuilder(
            animation: Listenable.merge([_controller, _blendController]),
            builder: (context, _) => _buildOrb(progress),
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
                onTapDown: (_) => _pressChanged(pressed: true),
                onTapUp: (_) => _pressChanged(pressed: false),
                onTapCancel: () => _pressChanged(pressed: false),
                customBorder: const CircleBorder(),
                child: ExcludeSemantics(child: orb),
              ),
            ),
    );
  }

  Widget _buildOrb(double progress) {
    _tick();
    _releaseTickerWhenSettled();
    final style = _displayStyle;
    final blend = _blendController.value;
    final throbScale = style.throbAmount > 0
        ? 1 - style.throbAmount * (1 - _wave)
        : 1.0;
    // A stage change swells the orb and settles back rather than easing
    // one way, so the change has a beat instead of a duration.
    final beat = _transitionStrength * math.sin(math.pi * blend);
    return Transform.scale(
      scale: throbScale + style.coreReact * _level + 0.05 * beat,
      child: CustomPaint(
        painter: VoiceOrbPainter(
          pulse: _controller.value,
          ringCount: style.ringCount,
          ringOpacity: style.ringOpacity,
          ringColor: style.ringColor,
          coreColor: style.coreColor,
          borderColor: style.borderColor,
          haloColor: style.haloColor,
          haloStrength:
              style.haloBase + style.haloReact * _level + 0.3 * beat,
          barLevels: style.barsOpacity > 0.01 ? _barLevels() : const [],
          barColor: style.barColor,
          barsOpacity: style.barsOpacity,
          progress: widget.progress == null ? null : progress,
          progressColor: style.progressColor,
          trackColor: AppColors.borderMedium,
          transition: blend,
          transitionStrength: _transitionStrength,
          releasedProgress: _releasedProgress,
        ),
        child: Center(
          child: Opacity(
            opacity:
                (style.iconOpacity * (style.breathes ? 0.45 + 0.55 * _wave : 1))
                    .clamp(0.0, 1.0),
            child: Icon(
              style.icon,
              size: widget.size * 0.24,
              color: style.iconColor,
            ),
          ),
        ),
      ),
    );
  }

  void _pressChanged({required bool pressed}) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  /// Which of the three things the orb can be doing a mode belongs to.
  ///
  /// Only crossing between them is a moment: the live orb swaps between
  /// listening, the user talking and the assistant talking several times
  /// a sentence, and announcing each one would be a strobe.
  static _OrbStage _stageOf(VoiceOrbMode mode) {
    return switch (mode) {
      VoiceOrbMode.connecting => _OrbStage.connecting,
      VoiceOrbMode.listening ||
      VoiceOrbMode.userSpeaking ||
      VoiceOrbMode.speaking => _OrbStage.live,
      VoiceOrbMode.idle || VoiceOrbMode.paused => _OrbStage.dormant,
    };
  }

  _VoiceOrbStyle get _displayStyle {
    final from = _blendFrom;
    final blend = _blendController.value;
    if (from == null || blend >= 1) {
      return _target;
    }
    return _VoiceOrbStyle.lerp(
      from,
      _target,
      Curves.easeOutCubic.transform(blend),
    );
  }

  /// Advances the per-frame quantities: the smoothed voice level and the
  /// waveform phase. Runs inside the animated builder so it only costs
  /// anything while a ticker is on.
  void _tick() {
    final now = DateTime.now();
    final dt = (now.difference(_lastTick).inMicroseconds / 1e6).clamp(
      0.0,
      0.05,
    );
    _lastTick = now;
    final activity = widget.activity;
    final targetLevel = switch (_target.levelSource) {
      _OrbLevelSource.none => 0.0,
      _OrbLevelSource.user => activity?.userLevel ?? 0,
      _OrbLevelSource.ai => activity?.aiLevel ?? 0,
    };
    final gain = targetLevel > _level ? 0.35 : 0.12;
    _level += (targetLevel - _level) * gain;
    _barPhase += dt * (5 + 9 * _level);
  }

  /// The idle bob keeps the bars visibly alive even in silence, so a quiet
  /// room still reads as "listening" rather than "frozen"; the voice level
  /// then scales the dance on top of it.
  List<double> _barLevels() {
    return [
      for (var index = 0; index < _barSeeds.length; index++)
        (0.14 +
                0.07 *
                    (0.5 +
                        0.5 *
                            math.sin(
                              _barPhase * 0.7 + _barSeeds[index] * 1.3,
                            )) +
                0.79 *
                    _level *
                    _barWeights[index] *
                    (0.6 + 0.4 * math.sin(_barPhase + _barSeeds[index])))
            .clamp(0.1, 1.0),
    ];
  }

  /// A single rise and fall over one cycle, so whatever it drives eases
  /// both ways instead of snapping back at the loop point.
  double get _wave {
    if (!_controller.isAnimating) {
      return 1;
    }
    return 1 - (_controller.value * 2 - 1).abs();
  }

  bool get _needsTicker => _target.animates;

  /// Keeps the pulse ticker off whenever the mode itself has nothing to
  /// animate, so a finished, failed or paused screen costs no frames once
  /// its entrance blend has settled.
  void _syncAnimation() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _blendController.value = 1;
      _blendFrom = null;
      _stopTicker();
      return;
    }
    _controller.duration = _target.period;
    if (_needsTicker == _controller.isAnimating) {
      return;
    }
    if (_needsTicker) {
      _lastTick = DateTime.now();
      _controller.repeat();
    } else {
      _stopTicker();
    }
  }

  /// Static modes settle by time rather than by an event, so the running
  /// ticker asks to be re-evaluated once the blend and level have decayed.
  void _releaseTickerWhenSettled() {
    if (!_controller.isAnimating || _needsTicker) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncAnimation();
      }
    });
  }

  void _stopTicker() {
    if (!_controller.isAnimating) {
      return;
    }
    _controller
      ..stop()
      ..value = 0;
  }
}

enum _OrbLevelSource { none, user, ai }

enum _OrbStage { dormant, connecting, live }

/// Everything one mode looks like, expressed in continuous quantities so
/// any two modes can be interpolated for a seamless transition.
class _VoiceOrbStyle {
  const _VoiceOrbStyle({
    required this.ringCount,
    required this.ringOpacity,
    required this.ringColor,
    required this.coreColor,
    required this.borderColor,
    required this.progressColor,
    required this.haloColor,
    required this.haloBase,
    required this.haloReact,
    required this.icon,
    required this.iconColor,
    required this.iconOpacity,
    required this.barColor,
    required this.barsOpacity,
    required this.breathes,
    required this.throbAmount,
    required this.coreReact,
    required this.levelSource,
    required this.period,
  });

  factory _VoiceOrbStyle.of(VoiceOrbMode mode) {
    return switch (mode) {
      VoiceOrbMode.idle => const _VoiceOrbStyle(
        ringCount: 2,
        ringOpacity: 1,
        ringColor: AppColors.inkMuted,
        coreColor: AppColors.ink,
        borderColor: AppColors.ink,
        progressColor: AppColors.green,
        haloColor: AppColors.greenBright,
        haloBase: 0,
        haloReact: 0,
        icon: Icons.mic_rounded,
        iconColor: AppColors.onDark,
        iconOpacity: 1,
        barColor: AppColors.greenBright,
        barsOpacity: 0,
        breathes: false,
        throbAmount: 0.04,
        coreReact: 0,
        levelSource: _OrbLevelSource.none,
        period: ProjectDuration.invite,
      ),
      VoiceOrbMode.connecting => const _VoiceOrbStyle(
        ringCount: 2,
        ringOpacity: 0.7,
        ringColor: AppColors.greenBright,
        coreColor: AppColors.ink,
        borderColor: AppColors.ink,
        progressColor: AppColors.greenBright,
        haloColor: AppColors.greenBright,
        haloBase: 0.24,
        haloReact: 0,
        icon: Icons.mic_rounded,
        iconColor: AppColors.onDark,
        iconOpacity: 0,
        barColor: AppColors.greenBright,
        barsOpacity: 0.7,
        breathes: false,
        throbAmount: 0.05,
        coreReact: 0,
        levelSource: _OrbLevelSource.none,
        period: ProjectDuration.pulse,
      ),
      VoiceOrbMode.listening => const _VoiceOrbStyle(
        ringCount: 2,
        ringOpacity: 1,
        ringColor: AppColors.greenBright,
        coreColor: AppColors.ink,
        borderColor: AppColors.ink,
        progressColor: AppColors.greenBright,
        haloColor: AppColors.greenBright,
        haloBase: 0.1,
        haloReact: 0.5,
        icon: Icons.mic_rounded,
        iconColor: AppColors.onDark,
        iconOpacity: 0,
        barColor: AppColors.greenBright,
        barsOpacity: 1,
        breathes: false,
        throbAmount: 0,
        coreReact: 0.04,
        levelSource: _OrbLevelSource.user,
        period: ProjectDuration.invite,
      ),
      VoiceOrbMode.userSpeaking => const _VoiceOrbStyle(
        ringCount: 0,
        ringOpacity: 0,
        ringColor: AppColors.greenBright,
        coreColor: AppColors.ink,
        borderColor: AppColors.ink,
        progressColor: AppColors.greenBright,
        haloColor: AppColors.greenBright,
        haloBase: 0.3,
        haloReact: 0.7,
        icon: Icons.mic_rounded,
        iconColor: AppColors.onDark,
        iconOpacity: 0,
        barColor: AppColors.greenBright,
        barsOpacity: 1,
        breathes: false,
        throbAmount: 0,
        coreReact: 0.06,
        levelSource: _OrbLevelSource.user,
        period: ProjectDuration.pulse,
      ),
      VoiceOrbMode.speaking => const _VoiceOrbStyle(
        ringCount: 3,
        ringOpacity: 1,
        ringColor: AppColors.greenBright,
        coreColor: AppColors.green,
        borderColor: AppColors.green,
        progressColor: AppColors.greenBright,
        haloColor: AppColors.greenMid,
        haloBase: 0.25,
        haloReact: 0.75,
        icon: Icons.volume_up_rounded,
        iconColor: AppColors.onDark,
        iconOpacity: 0,
        barColor: AppColors.onDark,
        barsOpacity: 1,
        breathes: false,
        throbAmount: 0,
        coreReact: 0.07,
        levelSource: _OrbLevelSource.ai,
        period: ProjectDuration.pulse,
      ),
      VoiceOrbMode.paused => const _VoiceOrbStyle(
        ringCount: 0,
        ringOpacity: 0,
        ringColor: AppColors.border,
        coreColor: AppColors.backgroundStone,
        borderColor: AppColors.borderMedium,
        progressColor: AppColors.green,
        haloColor: AppColors.greenBright,
        haloBase: 0,
        haloReact: 0,
        icon: Icons.mic_off_rounded,
        iconColor: AppColors.inkMuted,
        iconOpacity: 1,
        barColor: AppColors.greenBright,
        barsOpacity: 0,
        breathes: false,
        throbAmount: 0,
        coreReact: 0,
        levelSource: _OrbLevelSource.none,
        period: ProjectDuration.pulse,
      ),
    };
  }

  factory _VoiceOrbStyle.lerp(_VoiceOrbStyle a, _VoiceOrbStyle b, double t) {
    final iconSwaps = a.icon != b.icon;
    final iconOpacity =
        lerpDouble(a.iconOpacity, b.iconOpacity, t)! *
        (iconSwaps ? (t * 2 - 1).abs() : 1);
    return _VoiceOrbStyle(
      ringCount: b.ringCount > 0 ? b.ringCount : a.ringCount,
      ringOpacity: lerpDouble(
        a.ringCount > 0 ? a.ringOpacity : 0,
        b.ringCount > 0 ? b.ringOpacity : 0,
        t,
      )!,
      ringColor: Color.lerp(a.ringColor, b.ringColor, t)!,
      coreColor: Color.lerp(a.coreColor, b.coreColor, t)!,
      borderColor: Color.lerp(a.borderColor, b.borderColor, t)!,
      progressColor: Color.lerp(a.progressColor, b.progressColor, t)!,
      haloColor: Color.lerp(a.haloColor, b.haloColor, t)!,
      haloBase: lerpDouble(a.haloBase, b.haloBase, t)!,
      haloReact: lerpDouble(a.haloReact, b.haloReact, t)!,
      icon: t < 0.5 ? a.icon : b.icon,
      iconColor: Color.lerp(a.iconColor, b.iconColor, t)!,
      iconOpacity: iconOpacity,
      barColor: Color.lerp(a.barColor, b.barColor, t)!,
      barsOpacity: lerpDouble(a.barsOpacity, b.barsOpacity, t)!,
      breathes: t < 0.5 ? a.breathes : b.breathes,
      throbAmount: lerpDouble(a.throbAmount, b.throbAmount, t)!,
      coreReact: lerpDouble(a.coreReact, b.coreReact, t)!,
      levelSource: t < 0.5 ? a.levelSource : b.levelSource,
      period: b.period,
    );
  }

  final int ringCount;
  final double ringOpacity;
  final Color ringColor;
  final Color coreColor;
  final Color borderColor;
  final Color progressColor;
  final Color haloColor;
  final double haloBase;
  final double haloReact;
  final IconData icon;
  final Color iconColor;
  final double iconOpacity;
  final Color barColor;
  final double barsOpacity;
  final bool breathes;
  final double throbAmount;
  final double coreReact;
  final _OrbLevelSource levelSource;
  final Duration period;

  bool get animates {
    return (ringCount > 0 && ringOpacity > 0) ||
        breathes ||
        throbAmount > 0 ||
        barsOpacity > 0 ||
        levelSource != _OrbLevelSource.none;
  }
}
