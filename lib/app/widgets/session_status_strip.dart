import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';

/// The lines a status strip speaks during the connect and teardown waits.
///
/// Each feature words its own waits — the recorder's permission ask is
/// not the player's audio prep — but the strip that speaks them is one
/// widget, so the states that can go unnamed collapse into each other by
/// features passing the same string twice.
final class SessionStripCopy {
  const SessionStripCopy({
    required this.requestingPermission,
    required this.preparingAudio,
    required this.creatingTask,
    required this.connectingSocket,
    required this.waitingForStream,
    required this.stopping,
  });

  final String requestingPermission;
  final String preparingAudio;
  final String creatingTask;
  final String connectingSocket;
  final String waitingForStream;
  final String stopping;
}

/// The strip above a session's button, wearing whatever the moment needs.
///
/// During the connect steps it names what the wait is on; while the
/// session streams it shows whatever the feature hands it — a waveform,
/// a "Speaking…" line; a failure states what happened in one line. An
/// idle screen shows nothing, because the button already says it all.
///
/// Fixed-height so the button below never jumps as the content changes.
class SessionStatusStrip extends StatelessWidget {
  const SessionStatusStrip({
    required this.sessionState,
    required this.copy,
    required this.streaming,
    this.errorMessage,
    this.errorKey,
    super.key,
  });

  final RealtimeSessionState sessionState;
  final SessionStripCopy copy;

  /// What the strip shows while the session streams.
  final Widget streaming;

  final String? errorMessage;
  final Key? errorKey;

  /// The quiet voice every wait speaks in; exposed so a feature's
  /// [streaming] content can match it.
  static TextStyle? mutedStyle(BuildContext context) {
    return context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Center(child: _contentFor(context)),
    );
  }

  Widget _contentFor(BuildContext context) {
    final muted = mutedStyle(context);
    switch (sessionState) {
      case RealtimeSessionState.requestingPermission:
        return Text(copy.requestingPermission, style: muted);
      case RealtimeSessionState.preparingAudio:
        return Text(copy.preparingAudio, style: muted);
      case RealtimeSessionState.creatingTask:
        return Text(copy.creatingTask, style: muted);
      case RealtimeSessionState.connectingSocket:
        return Text(copy.connectingSocket, style: muted);
      // The cold start runs on someone else's cluster for up to a couple
      // of minutes; a wait that long has to say it is expected, or it
      // reads as stuck.
      case RealtimeSessionState.waitingForStream:
        return Text(
          copy.waitingForStream,
          style: muted,
          textAlign: TextAlign.center,
        );
      case RealtimeSessionState.streaming:
        return streaming;
      case RealtimeSessionState.stopping:
        return Text(copy.stopping, style: muted);
      case RealtimeSessionState.failure:
        final message = errorMessage;
        if (message == null || message.isEmpty) {
          return const SizedBox.shrink();
        }
        return Text(
          message,
          key: errorKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.error,
          ),
        );
      case RealtimeSessionState.idle:
      case RealtimeSessionState.completed:
        return const SizedBox.shrink();
    }
  }
}
