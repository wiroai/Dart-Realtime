import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/speech_to_text/service/transcription_session_snapshot.dart';

/// Commands a transcription session and reports it as snapshots.
///
/// Every command is a no-op once [dispose] has run.
abstract interface class TranscriptionSessionController {
  /// Emits on every session change, synchronously.
  Stream<TranscriptionSessionSnapshot> get snapshots;

  /// The latest published snapshot.
  TranscriptionSessionSnapshot get snapshot;

  /// The model this transcription runs against.
  ModelDefinition get model;

  /// Request values sent when the task is created.
  ModelParameterValues get parameters;

  /// Arbitrates which realtime feature owns the audio hardware.
  RealtimeSessionGuard get sessionGuard;

  Future<void> start();

  Future<void> stop();

  void clearTranscript();

  Future<void> dispose();
}
