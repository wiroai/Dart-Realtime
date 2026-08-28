import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/duration_extension.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

class SessionStatusLabel extends StatelessWidget {
  const SessionStatusLabel({required this.sessionState, super.key});

  final RealtimeSessionState sessionState;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Status: ${sessionState.name}',
      key: const ValueKey<String>('session-status'),
    );
  }
}

class ElapsedTimeLabel extends StatelessWidget {
  const ElapsedTimeLabel({required this.elapsed, super.key});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    return Text('Elapsed ${elapsed.clockLabel}');
  }
}

class SanitizedErrorText extends StatelessWidget {
  const SanitizedErrorText({required this.errorMessage, super.key});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage;
    if (message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      message,
      key: const ValueKey<String>('sanitized-error'),
      style: TextStyle(color: context.colorScheme.error),
    );
  }
}

class FixedModelLabel extends StatelessWidget {
  const FixedModelLabel({required this.model, super.key});

  final ModelDefinition model;

  @override
  Widget build(BuildContext context) {
    return Text(
      model.modelSlug,
      key: ValueKey<String>('model-${model.modelSlug}'),
    );
  }
}

class StartStopControls extends StatelessWidget {
  const StartStopControls({
    required this.sessionState,
    required this.startLabel,
    required this.stopLabel,
    required this.onStart,
    required this.onStop,
    this.sessionGuard,
    super.key,
  });

  final RealtimeSessionState sessionState;
  final String startLabel;
  final String stopLabel;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final RealtimeSessionGuard? sessionGuard;

  @override
  Widget build(BuildContext context) {
    final guard = sessionGuard;
    if (guard == null) {
      return _SessionControlButtons(
        sessionState: sessionState,
        startLabel: startLabel,
        stopLabel: stopLabel,
        onStart: onStart,
        onStop: onStop,
        anotherSessionActive: false,
      );
    }
    return ValueListenableBuilder<RealtimeSessionLease?>(
      valueListenable: guard,
      builder: (context, lease, _) {
        return _SessionControlButtons(
          sessionState: sessionState,
          startLabel: startLabel,
          stopLabel: stopLabel,
          onStart: onStart,
          onStop: onStop,
          anotherSessionActive: lease != null,
        );
      },
    );
  }
}

class _SessionControlButtons extends StatelessWidget {
  const _SessionControlButtons({
    required this.sessionState,
    required this.startLabel,
    required this.stopLabel,
    required this.onStart,
    required this.onStop,
    required this.anotherSessionActive,
  });

  final RealtimeSessionState sessionState;
  final String startLabel;
  final String stopLabel;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final bool anotherSessionActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FilledButton(
          key: const ValueKey<String>('start-control'),
          onPressed: sessionState.canStart && !anotherSessionActive
              ? onStart
              : null,
          child: Text(startLabel),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const ValueKey<String>('stop-control'),
          onPressed: sessionState.canStop ? onStop : null,
          child: Text(stopLabel),
        ),
      ],
    );
  }
}

class MicrophoneActivityLabel extends StatelessWidget {
  const MicrophoneActivityLabel({
    required this.microphoneActive,
    super.key,
  });

  final bool microphoneActive;

  @override
  Widget build(BuildContext context) {
    return Text(
      microphoneActive ? 'Microphone active' : 'Microphone idle',
    );
  }
}
