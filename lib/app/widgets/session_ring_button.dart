import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// The five faces a session's one button wears.
///
/// Both the recorder and the player run the same session lifecycle, so
/// they share one phase vocabulary: tap to start, a spinner for the
/// connect and teardown waits, a live face to stop, and a blocked face
/// while another feature holds the microphone.
enum SessionRingPhase { ready, blocked, connecting, live, stopping }

/// Maps the session lifecycle onto the button's phases.
///
/// [busy] is another feature holding the session lease; it only matters
/// while this session is idle, because a session already running is the
/// one holding it.
SessionRingPhase sessionRingPhaseFor(
  RealtimeSessionState state, {
  required bool busy,
}) {
  if (state == RealtimeSessionState.streaming) {
    return SessionRingPhase.live;
  }
  if (state == RealtimeSessionState.stopping) {
    return SessionRingPhase.stopping;
  }
  if (state.isActive) {
    return SessionRingPhase.connecting;
  }
  return busy ? SessionRingPhase.blocked : SessionRingPhase.ready;
}

/// One ring, one core, every session phase dressed differently.
///
/// The shape language the recorder and the player share: an outlined
/// ring whose colored core invites the tap, a spinner while the session
/// connects or winds down, and a live face that stops it. The hand never
/// has to move mid-session, because every phase is this same control.
///
/// The two faces differ only in dress: the recorder collapses its red
/// core into a square and pulses while live ([collapseWhenLive],
/// [pulseWhenLive]); the player swaps a play glyph for a stop glyph
/// ([readyIcon], [liveIcon]).
class SessionRingButton extends StatefulWidget {
  const SessionRingButton({
    required this.phase,
    required this.onStart,
    required this.onStop,
    required this.startSemanticLabel,
    required this.stopSemanticLabel,
    required this.cancelSemanticLabel,
    this.accent,
    this.onAccent,
    this.readyIcon,
    this.liveIcon,
    this.collapseWhenLive = false,
    this.pulseWhenLive = false,
    this.semanticsKey,
    super.key,
  });

  final SessionRingPhase phase;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final String startSemanticLabel;
  final String stopSemanticLabel;
  final String cancelSemanticLabel;

  /// Core color while the button is ready or live; defaults to primary.
  final Color? accent;

  /// Icon color on the accent core; defaults to onPrimary.
  final Color? onAccent;

  final IconData? readyIcon;
  final IconData? liveIcon;
  final bool collapseWhenLive;
  final bool pulseWhenLive;
  final Key? semanticsKey;

  /// Outer ring diameter, shared so every tab's session control — this
  /// button and the conversation orb — reads as the same size.
  static const double diameter = 96;

  /// The full box the button occupies, leaving the pulse ring room to
  /// travel without shifting the layout around it.
  static const double footprint = diameter + 24;

  @override
  State<SessionRingButton> createState() => _SessionRingButtonState();
}

class _SessionRingButtonState extends State<SessionRingButton>
    with SingleTickerProviderStateMixin {
  static const double _diameter = SessionRingButton.diameter;
  static const double _coreDiameter = 74;
  static const double _collapsedSide = 38;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(SessionRingButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _syncPulse() {
    final shouldPulse =
        widget.pulseWhenLive &&
        widget.phase == SessionRingPhase.live &&
        !MediaQuery.disableAnimationsOf(context);
    if (shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!shouldPulse && _pulseController.isAnimating) {
      _pulseController
        ..stop()
        ..reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final accent = widget.accent ?? colorScheme.primary;
    final onAccent = widget.onAccent ?? colorScheme.onPrimary;
    final (onTap, semanticLabel) = switch (widget.phase) {
      SessionRingPhase.ready => (widget.onStart, widget.startSemanticLabel),
      // A blocked start still answers the tap: the service refuses it
      // with the one-line reason, which beats a button that plays dead.
      SessionRingPhase.blocked => (widget.onStart, widget.startSemanticLabel),
      SessionRingPhase.connecting => (
        widget.onStop,
        widget.cancelSemanticLabel,
      ),
      SessionRingPhase.live => (widget.onStop, widget.stopSemanticLabel),
      SessionRingPhase.stopping => (null, widget.stopSemanticLabel),
    };
    final showSpinner =
        widget.phase == SessionRingPhase.connecting ||
        widget.phase == SessionRingPhase.stopping;
    final live = widget.phase == SessionRingPhase.live;
    final accented = widget.phase == SessionRingPhase.ready || live;
    final collapsed = live && widget.collapseWhenLive;
    final icon = live ? widget.liveIcon : widget.readyIcon;
    return Semantics(
      key: widget.semanticsKey,
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: SessionRingButton.footprint,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_pulseController.isAnimating)
              _PulseRing(
                controller: _pulseController,
                diameter: _diameter,
                color: accent,
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  width: 3,
                  color: colorScheme.outlineVariant,
                ),
              ),
              child: const SizedBox.square(dimension: _diameter),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: collapsed ? _collapsedSide : _coreDiameter,
              height: collapsed ? _collapsedSide : _coreDiameter,
              decoration: BoxDecoration(
                color: accented ? accent : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(
                  collapsed ? 8 : _coreDiameter / 2,
                ),
              ),
              child: !showSpinner && icon != null
                  ? Icon(
                      icon,
                      size: 38,
                      color: accented ? onAccent : colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
            if (showSpinner)
              SizedBox.square(
                dimension: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            SizedBox.square(
              dimension: _diameter,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({
    required this.controller,
    required this.diameter,
    required this.color,
  });

  final AnimationController controller;
  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return Opacity(
          opacity: (1 - t) * 0.35,
          child: Transform.scale(
            scale: 1 + 0.35 * t,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(width: 2, color: color),
              ),
              child: SizedBox.square(dimension: diameter),
            ),
          ),
        );
      },
    );
  }
}
