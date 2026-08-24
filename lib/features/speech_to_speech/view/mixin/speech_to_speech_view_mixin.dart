import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wiro_realtime/core/audio/voice_engine_pcm_audio.dart';
import 'package:wiro_realtime/core/auth/wiro_auth_headers.dart';
import 'package:wiro_realtime/core/network/dio_wiro_http_client.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_http_client.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/core/realtime/web_socket_realtime_socket_client.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/speech_to_speech_view.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';

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
    );
    _appLifecycleListener = AppLifecycleListener(
      onHide: _stopActiveSession,
      onPause: _stopActiveSession,
      onDetach: _stopActiveSession,
    );
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    speechToSpeechViewModel.dispose();
    _httpClient.close();
    super.dispose();
  }

  void _stopActiveSession() {
    if (speechToSpeechViewModel.state.sessionState.canStop) {
      unawaited(speechToSpeechViewModel.stop());
    }
  }
}
