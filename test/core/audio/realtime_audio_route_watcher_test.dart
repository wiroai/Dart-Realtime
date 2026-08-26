import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_route_watcher.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';

void main() {
  late _FakeRealtimeAudioSession audioSession;
  late StreamController<AudioPlaybackFailure> playbackFailures;
  late int stopRequests;
  late int routeChanges;
  late List<AudioPlaybackFailure> failures;
  late RealtimeAudioRouteWatcher watcher;

  setUp(() {
    audioSession = _FakeRealtimeAudioSession();
    playbackFailures = StreamController<AudioPlaybackFailure>();
    stopRequests = 0;
    routeChanges = 0;
    failures = [];
    watcher = RealtimeAudioRouteWatcher(
      audioSession: audioSession,
      playbackFailures: playbackFailures.stream,
      onShouldStop: () => stopRequests++,
      onRouteChanged: () => routeChanges++,
      onPlaybackFailure: failures.add,
    );
  });

  tearDown(() async {
    await watcher.dispose();
    await audioSession.close();
    await playbackFailures.close();
  });

  test('a beginning interruption requests a stop', () async {
    audioSession.interruptionController.add(RealtimeAudioInterruption.began);
    await _flush();

    expect(stopRequests, 1);
  });

  test('an ending interruption does not request a stop', () async {
    audioSession.interruptionController.add(RealtimeAudioInterruption.ended);
    await _flush();

    expect(stopRequests, isZero);
  });

  test('unplugging the output route requests a stop', () async {
    audioSession.becomingNoisyController.add(null);
    await _flush();

    expect(stopRequests, 1);
  });

  test('a route change is reported separately from a stop', () async {
    audioSession.routeChangeController.add(null);
    await _flush();

    expect(routeChanges, 1);
    expect(stopRequests, isZero);
  });

  test('playback failures reach the caller unchanged', () async {
    const failure = AudioPlaybackFailure();

    playbackFailures.add(failure);
    await _flush();

    expect(failures, [failure]);
  });

  test('disposal detaches every source', () async {
    await watcher.dispose();

    audioSession.interruptionController.add(RealtimeAudioInterruption.began);
    audioSession.becomingNoisyController.add(null);
    audioSession.routeChangeController.add(null);
    playbackFailures.add(const AudioPlaybackFailure());
    await _flush();

    expect(stopRequests, isZero);
    expect(routeChanges, isZero);
    expect(failures, isEmpty);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _FakeRealtimeAudioSession implements RealtimeAudioSession {
  final interruptionController = StreamController<RealtimeAudioInterruption>();
  final becomingNoisyController = StreamController<void>();
  final routeChangeController = StreamController<void>();

  @override
  Stream<RealtimeAudioInterruption> get interruptions =>
      interruptionController.stream;

  @override
  Stream<void> get becomingNoisy => becomingNoisyController.stream;

  @override
  Stream<void> get routeChanges => routeChangeController.stream;

  @override
  Future<AudioPreparationResult> prepare(RealtimeAudioProfile profile) async {
    return AudioPreparationResult.ready;
  }

  @override
  Future<void> deactivate() async {}

  @override
  Future<bool> setSpeakerEnabled({required bool enabled}) async => true;

  @override
  Future<bool> openSystemSettings() async => true;

  @override
  Future<void> dispose() async {}

  Future<void> close() async {
    await interruptionController.close();
    await becomingNoisyController.close();
    await routeChangeController.close();
  }
}
