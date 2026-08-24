import 'dart:async';
import 'dart:typed_data';

import 'package:audio_stream_player/audio_stream_player.dart';
import 'package:wiro_realtime/core/audio/audio_constants.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';

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
    final player = _requirePlayer();
    await player.stop();
    await player.play();
  }

  @override
  Future<Duration> bufferedDuration() {
    return _requirePlayer().bufferedDuration();
  }

  @override
  Future<void> setVolume(double volume) {
    return _requirePlayer().setVolume(volume);
  }

  @override
  Future<void> endOfStream() => _requirePlayer().endOfStream();

  @override
  Future<void> stop() => _requirePlayer().stop();

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _underrunSubscription?.cancel();
    await _player?.dispose();
    _player = null;
    await _underrunController.close();
  }

  AudioStreamPlayer _requirePlayer() {
    final player = _player;
    if (player == null || _disposed) {
      throw StateError('The PCM playback sink is not initialized.');
    }
    return player;
  }
}
