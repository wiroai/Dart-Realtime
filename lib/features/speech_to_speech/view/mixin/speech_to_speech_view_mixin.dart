import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wiro_realtime/core/audio/pcm_noise_gate.dart';
import 'package:wiro_realtime/core/audio/voice_engine_pcm_audio.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_dependencies.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/speech_to_speech_session_service.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/speech_to_speech_view.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';

/// Builds the conversation session but never opens it.
///
/// A session is a billed Wiro task, so reaching the tab cannot be what
/// creates one: a stray tap, a hot restart or a lifecycle resume would each
/// spend the reader's credits without them asking. The orb is the consent,
/// and it is also what makes the parameters above it mean something — they
/// are read while the task is being created.
mixin SpeechToSpeechViewMixin on State<SpeechToSpeechView> {
  late final SpeechToSpeechViewModel speechToSpeechViewModel;
  late final RealtimeSessionDependencies _dependencies;
  late final AppLifecycleListener _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    _dependencies = RealtimeSessionDependencies(
      credentials: widget.credentials,
      // Measured ready waits sit around thirteen seconds — a hair under
      // the default — and the socket replays nothing to a subscriber
      // that arrives after an event fired, so a wait that gives up
      // early strands a task that was about to speak.
      readyTimeout: const Duration(seconds: 60),
    );
    final audio = VoiceEnginePcmAudioPair();
    speechToSpeechViewModel = SpeechToSpeechViewModel(
      sessionService: SpeechToSpeechSessionService(
        audioSession: widget.audioSession,
        apiClient: _dependencies.apiClient,
        sessionFactory: _dependencies.createSession,
        recorder: audio.recorder,
        player: audio.player,
        sessionGuard: widget.sessionGuard,
        noiseGate: PcmNoiseGate(),
      ),
    );
    _appLifecycleListener = AppLifecycleListener(
      onHide: _holdSession,
      onPause: _holdSession,
      // A detaching app has no return, so there is nothing to hold and a
      // task nobody will ever reconnect to must be told to stop.
      onDetach: _stopActiveSession,
      onShow: _resumeSession,
      onRestart: _resumeSession,
    );
  }

  @override
  void didUpdateWidget(SpeechToSpeechView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible == oldWidget.isVisible) {
      return;
    }
    if (widget.isVisible) {
      _resumeSession();
    } else {
      _holdSession();
    }
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    speechToSpeechViewModel.dispose();
    _dependencies.close();
    super.dispose();
  }

  /// Leaving the conversation silences it at once, but the task is kept for
  /// a short while so coming back continues it rather than starting over.
  void _holdSession() {
    unawaited(speechToSpeechViewModel.suspend());
  }

  void _resumeSession() {
    if (!widget.isVisible) {
      return;
    }
    unawaited(speechToSpeechViewModel.resume());
  }

  void _stopActiveSession() {
    if (speechToSpeechViewModel.state.sessionState.canStop) {
      unawaited(speechToSpeechViewModel.stop());
    }
  }
}
