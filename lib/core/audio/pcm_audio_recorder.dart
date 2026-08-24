import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/audio_constants.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/audio/bounded_pcm_queue.dart';
import 'package:wiro_realtime/core/audio/pcm_chunker.dart';

enum PcmCaptureProfile {
  conversation,
  transcription,
}

abstract interface class PcmCaptureSource {
  bool get isRecording;

  Future<Stream<Uint8List>> start(PcmCaptureProfile profile);

  Future<void> stop();

  Future<void> dispose();
}

abstract interface class PcmAudioRecorder {
  bool get isRecording;

  bool get isMuted;

  int get mutedSourceBuffers;

  int get queueHighWaterMarkInChunks;

  Future<Stream<Uint8List>> start(PcmCaptureProfile profile);

  void setMuted({required bool muted});

  Future<void> stop();

  Future<void> dispose();
}

final class BufferedPcmAudioRecorder implements PcmAudioRecorder {
  BufferedPcmAudioRecorder(
    this._source, {
    this.queueCapacityInChunks = 50,
  });

  final PcmCaptureSource _source;
  final int queueCapacityInChunks;

  StreamSubscription<Uint8List>? _sourceSubscription;
  BoundedPcmQueue? _queue;
  PcmChunker? _chunker;
  late Stream<Uint8List> _stream;
  AudioCaptureFailure? _captureFailure;
  bool _recording = false;
  bool _muted = false;
  bool _disposed = false;
  int _captureGeneration = 0;
  int _mutedSourceBuffers = 0;
  int _queueHighWaterMarkInChunks = 0;

  @override
  bool get isRecording => _recording;

  @override
  bool get isMuted => _muted;

  @override
  int get mutedSourceBuffers => _mutedSourceBuffers;

  @override
  int get queueHighWaterMarkInChunks =>
      _queue?.highWaterMarkInChunks ?? _queueHighWaterMarkInChunks;

  @override
  Future<Stream<Uint8List>> start(PcmCaptureProfile profile) async {
    if (_disposed) {
      throw const AudioCaptureFailure();
    }
    if (_recording) {
      return _stream;
    }

    final queue = BoundedPcmQueue(
      capacityInChunks: queueCapacityInChunks,
    );
    final chunker = PcmChunker(
      chunkSizeInBytes: AudioConstants.pcmBytesPerChunk,
    );
    _queue = queue;
    _chunker = chunker;
    _captureFailure = null;
    _captureGeneration++;

    final Stream<Uint8List> sourceStream;
    try {
      sourceStream = await _source.start(profile);
    } on Object {
      queue.close();
      throw const AudioCaptureFailure();
    }

    _recording = true;
    _stream = _drain(queue);
    _sourceSubscription = sourceStream.listen(
      _handleSourceData,
      onError: _handleSourceError,
      onDone: _handleSourceDone,
    );
    return _stream;
  }

  @override
  void setMuted({required bool muted}) {
    _muted = muted;
    if (muted) {
      _captureGeneration++;
      _queue?.clear();
      _chunker?.reset();
    }
  }

  @override
  Future<void> stop() async {
    _recording = false;
    _captureGeneration++;
    await _sourceSubscription?.cancel();
    _sourceSubscription = null;
    _queue
      ?..clear()
      ..close();
    _chunker?.reset();
    await _source.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
    await _source.dispose();
  }

  void _handleSourceData(Uint8List bytes) {
    if (!_recording) {
      return;
    }
    if (_muted) {
      _mutedSourceBuffers++;
      return;
    }
    final subscription = _sourceSubscription;
    final generation = _captureGeneration;
    subscription?.pause();
    unawaited(
      _enqueue(bytes, generation).whenComplete(() {
        if (_recording && !_disposed) {
          subscription?.resume();
        }
      }),
    );
  }

  Future<void> _enqueue(Uint8List bytes, int generation) async {
    final queue = _queue;
    final chunker = _chunker;
    if (queue == null || chunker == null) {
      return;
    }
    for (final chunk in chunker.add(bytes)) {
      if (!_isCurrent(generation)) {
        return;
      }
      await queue.add(chunk);
      if (queue.highWaterMarkInChunks > _queueHighWaterMarkInChunks) {
        _queueHighWaterMarkInChunks = queue.highWaterMarkInChunks;
      }
      if (!_isCurrent(generation)) {
        queue.clear();
        return;
      }
    }
  }

  bool _isCurrent(int generation) {
    return _recording && !_muted && generation == _captureGeneration;
  }

  void _handleSourceError(Object _) {
    _captureFailure = const AudioCaptureFailure();
    _recording = false;
    _queue?.close();
    unawaited(_source.stop());
  }

  void _handleSourceDone() {
    _recording = false;
    _queue?.close();
  }

  Stream<Uint8List> _drain(BoundedPcmQueue queue) async* {
    await for (final chunk in queue.drain()) {
      yield chunk;
    }
    final failure = _captureFailure;
    if (failure != null) {
      throw failure;
    }
  }
}
