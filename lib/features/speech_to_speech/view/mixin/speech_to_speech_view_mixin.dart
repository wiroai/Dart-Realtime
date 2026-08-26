import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wiro_realtime/core/audio/pcm_noise_gate.dart';
import 'package:wiro_realtime/core/audio/voice_engine_pcm_audio.dart';
import 'package:wiro_realtime/core/auth/wiro_auth_headers.dart';
import 'package:wiro_realtime/core/network/dio_wiro_http_client.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_http_client.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/core/realtime/web_socket_realtime_socket_client.dart';
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
  late final WiroHttpClient _httpClient;
  late final AppLifecycleListener _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    _httpClient = DioWiroHttpClient();
    final audio = VoiceEnginePcmAudioPair();
    speechToSpeechViewModel = SpeechToSpeechViewModel(
      sessionService: SpeechToSpeechSessionService(
        audioSession: widget.audioSession,
        apiClient: DefaultWiroApiClient(
          _httpClient,
          WiroAuthHeaders(credentials: widget.credentials),
        ),
        sessionFactory: ({required taskId, required taskToken}) =>
            RealtimeSession(
              socketClient: WebSocketRealtimeSocketClient(),
              taskId: taskId,
              taskToken: taskToken,
            ),
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
    _httpClient.close();
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
