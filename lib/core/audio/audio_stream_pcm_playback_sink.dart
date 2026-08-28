import 'dart:async';
import 'dart:typed_data';

import 'package:audio_stream_player/audio_stream_player.dart';
import 'package:wiro_realtime/core/audio/audio_constants.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';

/// Plays PCM through `audio_stream_player`, one native player per
/// playback session.
///
/// The native player keeps its `AVAudioEngine` alive between plays, and
/// an engine that lived through an audio session deactivation can come
/// back as a zombie: it reports itself running while its IO unit is
/// gone, and the next `play()` raises an NSException Swift cannot catch
/// — the process dies. No live playback ever spans a deactivation here,
/// so [stop] discards the native player with its engine, and the next
/// session builds a fresh one against whatever audio session is active
/// then.
final class AudioStreamPcmPlaybackSink implements PcmPlaybackSink {
  final StreamController<void> _underrunController =
      StreamController<void>.broadcast(sync: true);

  AudioStreamPlayer? _player;
  StreamSubscription<void>? _underrunSubscription;
  bool _disposed = false;

  @override
  Stream<void> get underruns => _underrunController.stream;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('The PCM playback sink is disposed.');
    }
    if (_player == null) {
      final player = await AudioStreamPlayer.create(
        sampleRate: AudioConstants.sampleRateHz,
        configureAudioSession: false,
      );
      _player = player;
      _underrunSubscription = player.onUnderrun.listen((_) {
        if (!_underrunController.isClosed) {
          _underrunController.add(null);
        }
      });
    }
  }

  @override
  Future<void> play() => _requirePlayer().play();

  @override
  Future<void> feed(Uint8List chunk) => _requirePlayer().feed(chunk);

  @override
  Future<void> flush() async {
    final player = _player;
    if (player == null) {
      return;
    }
    await player.stop();
    await player.play();
  }

  @override
  Future<Duration> bufferedDuration() async {
    final player = _player;
    if (player == null) {
      return Duration.zero;
    }
    return player.bufferedDuration();
  }

  @override
  Future<void> setVolume(double volume) async {
    await _player?.setVolume(volume);
  }

  @override
  Future<void> endOfStream() async {
    await _player?.endOfStream();
  }

  @override
  Future<void> stop() => _discardPlayer();

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _discardPlayer();
    await _underrunController.close();
  }

  Future<void> _discardPlayer() async {
    final player = _player;
    if (player == null) {
      return;
    }
    _player = null;
    await _underrunSubscription?.cancel();
    _underrunSubscription = null;
    try {
      await player.stop();
    } finally {
      await player.dispose();
    }
  }

  AudioStreamPlayer _requirePlayer() {
    final player = _player;
    if (player == null || _disposed) {
      throw StateError('The PCM playback sink is not initialized.');
    }
    return player;
  }
}
