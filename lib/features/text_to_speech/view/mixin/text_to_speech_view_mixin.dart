import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wiro_realtime/core/audio/audio_stream_pcm_playback_sink.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/core/auth/wiro_auth_headers.dart';
import 'package:wiro_realtime/core/network/dio_wiro_http_client.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_http_client.dart';
import 'package:wiro_realtime/core/realtime/realtime_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/core/realtime/web_socket_realtime_socket_client.dart';
import 'package:wiro_realtime/features/text_to_speech/service/text_to_speech_session_service.dart';
import 'package:wiro_realtime/features/text_to_speech/view/text_to_speech_view.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/text_to_speech_view_model.dart';

mixin TextToSpeechViewMixin on State<TextToSpeechView> {
  late final TextToSpeechViewModel textToSpeechViewModel;
  late final WiroHttpClient _httpClient;
  late final AppLifecycleListener _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    _httpClient = DioWiroHttpClient();
    textToSpeechViewModel = TextToSpeechViewModel(
      sessionService: TextToSpeechSessionService(
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
        player: QueuedPcmAudioPlayer(
          AudioStreamPcmPlaybackSink(),
        ),
        sessionGuard: widget.sessionGuard,
      ),
    );
    _appLifecycleListener = AppLifecycleListener(
      onHide: _stopActiveSession,
      onPause: _stopActiveSession,
      onDetach: _stopActiveSession,
    );
  }

  /// Leaving the tab is leaving the session: speech nobody is on the tab
  /// to hear should not keep playing, and the task behind it should not
  /// keep billing.
  @override
  void didUpdateWidget(TextToSpeechView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible && !widget.isVisible) {
      _stopActiveSession();
    }
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    textToSpeechViewModel.dispose();
    _httpClient.close();
    super.dispose();
  }

  void _stopActiveSession() {
    if (textToSpeechViewModel.state.sessionState.canStop) {
      unawaited(textToSpeechViewModel.stop());
    }
  }
}
