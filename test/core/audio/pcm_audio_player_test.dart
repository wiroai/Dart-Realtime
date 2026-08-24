import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';

void main() {
  test('audio failures expose stable machine-readable codes', () {
    expect(
      const AudioPlaybackFailure().code,
      AudioFailureCode.playbackUnavailable,
    );
    expect(
      const AudioCaptureFailure().code,
      AudioFailureCode.captureUnavailable,
    );
  });

  test('feeds queued PCM chunks to the sink in FIFO order', () async {
    final sink = FakePcmPlaybackSink();
    final player = QueuedPcmAudioPlayer(sink);
    addTearDown(player.dispose);

    await player.start();
    await player.enqueue(Uint8List.fromList([1]));
    await player.enqueue(Uint8List.fromList([2]));
    await player.complete();

    expect(sink.fedChunks, [
      [1],
      [2],
    ]);
    expect(sink.endOfStreamCalls, 1);
    expect(player.isPlaying, isFalse);
  });

  test('speaker disable flushes audio and re-enable accepts new PCM', () async {
    final sink = FakePcmPlaybackSink();
    final player = QueuedPcmAudioPlayer(sink);
    addTearDown(player.dispose);

    await player.start();
    await player.setEnabled(enabled: false);
    await player.enqueue(Uint8List.fromList([1, 2]));
    await player.setEnabled(enabled: true);
    await player.enqueue(Uint8List.fromList([3, 4]));
    await player.complete();

    expect(sink.fedChunks, [
      [3, 4],
    ]);
    expect(sink.volumes, [1, 0, 1]);
    expect(sink.stopCalls, 1);
    expect(player.isEnabled, isTrue);
  });

  test('reports sanitized playback failures', () async {
    final sink = FakePcmPlaybackSink(failFeed: true);
    final player = QueuedPcmAudioPlayer(sink);
    addTearDown(player.dispose);
    final failure = player.failures.first;

    await player.start();
    await player.enqueue(Uint8List.fromList([1]));

    expect(await failure, isA<AudioPlaybackFailure>());
    expect((await failure).toString(), isNot(contains('platform')));
  });

  test('repeated lifecycle calls initialize and dispose once', () async {
    final sink = FakePcmPlaybackSink();
    final player = QueuedPcmAudioPlayer(sink);

    await player.start();
    await player.stop();
    await player.start();
    await player.complete();
    await player.dispose();
    await player.dispose();

    expect(sink.initializeCalls, 1);
    expect(sink.playCalls, 2);
    expect(sink.disposeCalls, 1);
  });
}

final class FakePcmPlaybackSink implements PcmPlaybackSink {
  FakePcmPlaybackSink({this.failFeed = false});

  final bool failFeed;
  final List<List<int>> fedChunks = [];
  final List<double> volumes = [];

  int initializeCalls = 0;
  int playCalls = 0;
  int endOfStreamCalls = 0;
  int stopCalls = 0;
  int flushCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<void> get underruns => const Stream.empty();

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> feed(Uint8List chunk) async {
    if (failFeed) {
      throw StateError('private platform failure');
    }
    fedChunks.add(List<int>.from(chunk));
  }

  @override
  Future<void> flush() async {
    flushCalls++;
    fedChunks.clear();
  }

  @override
  Future<Duration> bufferedDuration() async => Duration.zero;

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> endOfStream() async {
    endOfStreamCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
