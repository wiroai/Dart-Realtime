import 'dart:async';
import 'dart:typed_data';

import 'package:wiro_realtime/core/audio/pcm_level_meter.dart';
import 'package:wiro_realtime/core/audio/pcm_noise_gate.dart';

/// Gates microphone chunks, measures them, and notices when capture dies.
///
/// Healthy capture produces fifty chunks a second no matter how quiet the
/// room is, so a few silent seconds can only mean the pipeline broke. The
/// stall callback is pure timing: the caller still decides whether that
/// stall is current — muted capture, a superseded operation, a session
/// that is no longer streaming.
final class ConversationMicPipeline {
  ConversationMicPipeline({
    required this.onStall,
    this.noiseGate,
    this.stallTimeout = const Duration(seconds: 3),
  });

  final void Function() onStall;
  final PcmNoiseGate? noiseGate;
  final Duration stallTimeout;

  Timer? _watchdog;
  DateTime _lastChunkAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  /// Gates one chunk and measures it, recording capture liveness.
  ({Uint8List gated, double level}) process(
    Uint8List chunk, {
    required bool assistantAudible,
  }) {
    _lastChunkAt = DateTime.now();
    final gate = noiseGate;
    // While the assistant is audible the gate demands barge-in loudness,
    // so speaker echo the AEC misses cannot reach the server and come
    // back as a transcript the user never said.
    final gated =
        gate?.process(chunk, assistantAudible: assistantAudible) ?? chunk;
    // The gate measured the chunk on its way through; reusing that level
    // spares a second RMS pass over the same bytes for every chunk.
    final level = gate?.lastOutputLevel ?? pcmNormalizedLevel(chunk);
    return (gated: gated, level: level);
  }

  /// Muted capture legitimately delivers nothing; the stall clock only
  /// starts once the microphone is expected to speak again.
  void markAlive() {
    _lastChunkAt = DateTime.now();
  }

  void startWatchdog() {
    if (_disposed) {
      return;
    }
    _watchdog?.cancel();
    _lastChunkAt = DateTime.now();
    final tick = stallTimeout ~/ 2 < const Duration(milliseconds: 100)
        ? const Duration(milliseconds: 100)
        : stallTimeout ~/ 2;
    _watchdog = Timer.periodic(tick, (_) => _checkStall());
  }

  void stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  void dispose() {
    _disposed = true;
    stopWatchdog();
  }

  void _checkStall() {
    if (_disposed) {
      return;
    }
    if (DateTime.now().difference(_lastChunkAt) < stallTimeout) {
      return;
    }
    onStall();
  }
}
