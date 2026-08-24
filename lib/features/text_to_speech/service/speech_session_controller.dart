import 'package:flutter/foundation.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/model_parameter_values.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/text_to_speech/service/speech_session_snapshot.dart';

/// Commands a text-to-speech session and reports synchronous snapshots.
abstract interface class SpeechSessionController {
  Stream<SpeechSessionSnapshot> get snapshots;

  SpeechSessionSnapshot get snapshot;

  ModelParameterValues get parameters;

  RealtimeSessionGuard get sessionGuard;

  ValueNotifier<String> get promptNotifier;

  void selectModel(ModelDefinition model);

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}
