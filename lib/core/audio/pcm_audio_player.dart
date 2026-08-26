import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/bounded_pcm_queue.dart';

abstract interface class PcmPlaybackSink {
  Stream<void> get underruns;

  Future<void> initialize();

  Future<void> play();

  Future<void> feed(Uint8List chunk);

  /// Discards audio already handed to the platform without ending playback.
  Future<void> flush();

  Future<Duration> bufferedDuration();

  Future<void> setVolume(double volume);

  Future<void> endOfStream();

  Future<void> stop();

  Future<void> dispose();
}

abstract interface class PcmAudioPlayer {
  bool get isPlaying;

  bool get isEnabled;

  Stream<AudioPlaybackFailure> get failures;

  int get droppedChunks;

  int get queueHighWaterMarkInChunks;

  int get maximumFeedLatencyMicros;

  int get underrunCount;

  Future<void> start();

  bool tryEnqueue(Uint8List chunk);

  Future<void> enqueue(Uint8List chunk);

  /// Drops pending audio while keeping the playback session alive.
  void flush();

  /// Plays out what is already queued, then ends the stream.
  ///
  /// Returns even when the sink stopped draining: the queued tail is worth
  /// waiting for, but not indefinitely, since the caller ending a
  /// conversation cannot report that it ended until this returns.
  Future<void> complete();

  Future<void> setEnabled({required bool enabled});

  Future<void> stop();

  Future<void> dispose();
}

final class QueuedPcmAudioPlayer implements PcmAudioPlayer {
  QueuedPcmAudioPlayer(
    this._sink, {
    this.queueCapacityInChunks = 50,
    this.maxNativeBufferDuration = const Duration(seconds: 2),
    this.backpressurePollInterval = const Duration(milliseconds: 10),
    this.drainTimeout = const Duration(seconds: 5),
  }) {
    _underrunSubscription = _sink.underruns.listen((_) {
      _underrunCount++;
    });
  }

  final PcmPlaybackSink _sink;
  final int queueCapacityInChunks;
  final Duration maxNativeBufferDuration;
  final Duration backpressurePollInterval;

  /// How long [complete] waits for the queued tail to actually be heard.
  ///
  /// Draining is bounded by the queue and the native buffer, so a healthy
  /// sink finishes in a second or two. A sink that stopped consuming never
  /// finishes at all — an engine torn down under a route change, a task the
  /// server has just ended — and waiting on it forever costs far more than
  /// the tail: the screen keeps showing a live conversation long after the
  /// microphone has stopped.
  final Duration drainTimeout;
  final StreamController<AudioPlaybackFailure> _failureController =
      StreamController<AudioPlaybackFailure>.broadcast(sync: true);
  late final StreamSubscription<void> _underrunSubscription;

  BoundedPcmQueue? _queue;
  Future<void>? _worker;
  bool _initialized = false;
  bool _playing = false;
  bool _enabled = true;
  bool _disposed = false;
  int _playbackGeneration = 0;
  int _droppedChunks = 0;
  int _maximumFeedLatencyMicros = 0;
  int _queueHighWaterMarkInChunks = 0;
  int _underrunCount = 0;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isEnabled => _enabled;

  @override
  Stream<AudioPlaybackFailure> get failures => _failureController.stream;

  @override
  int get droppedChunks => _droppedChunks;

  @override
  int get queueHighWaterMarkInChunks =>
      _queue?.highWaterMarkInChunks ?? _queueHighWaterMarkInChunks;

  @override
  int get maximumFeedLatencyMicros => _maximumFeedLatencyMicros;

  @override
  int get underrunCount => _underrunCount;

  @override
  Future<void> start() async {
    if (_disposed) {
      throw const AudioPlaybackFailure();
    }
    if (_playing) {
      return;
    }

    try {
      if (!_initialized) {
        await _sink.initialize();
        _initialized = true;
      }
      final queue = BoundedPcmQueue(
        capacityInChunks: queueCapacityInChunks,
      );
      _queue = queue;
      _playing = true;
      _playbackGeneration++;
      await _sink.setVolume(_enabled ? 1 : 0);
      await _sink.play();
      _worker = _consume(queue);
    } on Object {
      _playing = false;
      _queue?.close();
      throw const AudioPlaybackFailure();
    }
  }

  @override
  bool tryEnqueue(Uint8List chunk) {
    if (!_playing || chunk.isEmpty) {
      return false;
    }
    if (!_enabled) {
      return true;
    }
    final added = _queue?.tryAdd(chunk) ?? false;
    if (!added) {
      _droppedChunks++;
    } else {
      final highWaterMark = _queue?.highWaterMarkInChunks ?? 0;
      if (highWaterMark > _queueHighWaterMarkInChunks) {
        _queueHighWaterMarkInChunks = highWaterMark;
      }
    }
    return added;
  }

  @override
  Future<void> enqueue(Uint8List chunk) async {
    if (!_playing || !_enabled || chunk.isEmpty) {
      return;
    }
    await _queue?.add(chunk);
  }

  @override
  void flush() {
    if (!_playing) {
      return;
    }
    _playbackGeneration++;
    _queue?.clear();
    unawaited(_flushSink());
  }

  @override
  Future<void> complete() async {
    if (!_playing) {
      return;
    }
    _queue?.close();
    try {
      await _worker?.timeout(drainTimeout);
      if (!_playing || _disposed) {
        return;
      }
      if (_enabled) {
        await _sink.endOfStream().timeout(drainTimeout);
      }
      _playing = false;
      _queue = null;
      _worker = null;
    } on TimeoutException {
      _abandonTail();
    } on Object {
      _reportFailure();
    }
  }

  /// Lets go of audio a stalled sink is never going to play.
  ///
  /// The worker parks on native backpressure until [_playing] goes false, so
  /// clearing the flag is what unwinds it; awaiting it here would only wait
  /// on the same stalled sink a second time.
  void _abandonTail() {
    _playing = false;
    _queue
      ?..clear()
      ..close();
    _queue = null;
    _worker = null;
    unawaited(_stopAfterFailure());
  }

  @override
  Future<void> setEnabled({required bool enabled}) async {
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    _playbackGeneration++;
    if (!enabled) {
      _queue?.clear();
    }
    if (_initialized) {
      try {
        if (enabled) {
          await _sink.setVolume(1);
          if (_playing) {
            await _sink.play();
          }
        } else {
          await _sink.setVolume(0);
          await _sink.stop();
        }
      } on Object {
        _reportFailure();
      }
    }
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _playbackGeneration++;
    _queue
      ?..clear()
      ..close();
    try {
      await _worker?.timeout(drainTimeout);
    } on TimeoutException {
      // A sink wedged mid-feed cannot hold up a shutdown; the retry path
      // and the failure path both run through here.
    }
    _queue = null;
    _worker = null;
    if (_initialized) {
      try {
        await _sink.stop();
      } on Object {
        _reportFailure();
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
    if (_initialized) {
      await _sink.dispose();
    }
    await _underrunSubscription.cancel();
    await _failureController.close();
  }

  Future<void> _consume(BoundedPcmQueue queue) async {
    try {
      await for (final chunk in queue.drain()) {
        if (!_playing) {
          return;
        }
        if (!_enabled) {
          continue;
        }
        final generation = _playbackGeneration;
        await _waitForNativeCapacity();
        if (!_playing) {
          return;
        }
        if (!_enabled || generation != _playbackGeneration) {
          continue;
        }
        final stopwatch = Stopwatch()..start();
        await _sink.feed(chunk);
        stopwatch.stop();
        if (stopwatch.elapsedMicroseconds > _maximumFeedLatencyMicros) {
          _maximumFeedLatencyMicros = stopwatch.elapsedMicroseconds;
        }
      }
    } on Object {
      _reportFailure();
    }
  }

  Future<void> _flushSink() async {
    if (!_initialized) {
      return;
    }
    try {
      await _sink.flush();
    } on Object {
      _reportFailure();
    }
  }

  Future<void> _waitForNativeCapacity() async {
    while (_playing) {
      final bufferedDuration = await _sink.bufferedDuration();
      if (bufferedDuration < maxNativeBufferDuration) {
        return;
      }
      await Future<void>.delayed(backpressurePollInterval);
    }
  }

  void _reportFailure() {
    const failure = AudioPlaybackFailure();
    _playing = false;
    _queue
      ?..clear()
      ..close();
    if (!_failureController.isClosed) {
      _failureController.add(failure);
    }
    unawaited(_stopAfterFailure());
  }

  Future<void> _stopAfterFailure() async {
    if (!_initialized) {
      return;
    }
    try {
      await _sink.stop();
    } on Object {
      // Recovery is best effort after a playback failure.
    }
  }
}
