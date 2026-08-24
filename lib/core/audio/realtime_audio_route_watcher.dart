import 'dart:async';

import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';

/// Owns the audio subscriptions that can force a realtime session to end, and
/// reports them as intent rather than as raw platform events.
///
/// Both an interruption and an unplugged output route mean the same thing to a
/// caller — stop now — so they collapse into `onShouldStop`. Deciding whether
/// the session is in a state that can act on that stays with the caller,
/// keeping session state out of this class.
final class RealtimeAudioRouteWatcher {
  RealtimeAudioRouteWatcher({
    required RealtimeAudioSession audioSession,
    required Stream<AudioPlaybackFailure> playbackFailures,
    required void Function() onShouldStop,
    required void Function() onRouteChanged,
    required void Function(AudioPlaybackFailure failure) onPlaybackFailure,
  }) {
    _subscriptions = [
      playbackFailures.listen(onPlaybackFailure),
      audioSession.interruptions.listen((interruption) {
        if (interruption == RealtimeAudioInterruption.began) {
          onShouldStop();
        }
      }),
      audioSession.becomingNoisy.listen((_) => onShouldStop()),
      audioSession.routeChanges.listen((_) => onRouteChanged()),
    ];
  }

  late final List<StreamSubscription<void>> _subscriptions;

  Future<void> dispose() async {
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
  }
}
