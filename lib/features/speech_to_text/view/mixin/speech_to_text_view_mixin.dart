import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';
import 'package:wiro_realtime/core/audio/record_pcm_capture_source.dart';
import 'package:wiro_realtime/core/auth/wiro_auth_headers.dart';
import 'package:wiro_realtime/core/network/dio_wiro_http_client.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_http_client.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/core/realtime/web_socket_realtime_socket_client.dart';
import 'package:wiro_realtime/features/speech_to_text/view/speech_to_text_view.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/speech_to_text_view_model.dart';

mixin SpeechToTextViewMixin on State<SpeechToTextView> {
  late final SpeechToTextViewModel speechToTextViewModel;
  late final WiroHttpClient _httpClient;
  late final AppLifecycleListener _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    _httpClient = DioWiroHttpClient();
    speechToTextViewModel = SpeechToTextViewModel(
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
      recorder: BufferedPcmAudioRecorder(
        RecordPcmCaptureSource(),
      ),
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
    speechToTextViewModel.dispose();
    _httpClient.close();
    super.dispose();
  }

  void _stopActiveSession() {
    if (speechToTextViewModel.state.sessionState.canStop) {
      unawaited(speechToTextViewModel.stop());
    }
  }
}
