import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wiro_realtime/core/audio/audio_stream_pcm_playback_sink.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_player.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_dependencies.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/text_to_speech/service/text_to_speech_session_service.dart';
import 'package:wiro_realtime/features/text_to_speech/view/text_to_speech_view.dart';
import 'package:wiro_realtime/features/text_to_speech/view_model/text_to_speech_view_model.dart';

mixin TextToSpeechViewMixin on State<TextToSpeechView> {
  late final TextToSpeechViewModel textToSpeechViewModel;
  late final RealtimeSessionDependencies _dependencies;
  late final AppLifecycleListener _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    _dependencies = RealtimeSessionDependencies(
      credentials: widget.credentials,
      // The MOSS TTS worker cold-starts in about a minute, and the
      // socket replays nothing to a subscriber that arrives after an
      // event fired. The first subscription therefore has to outlive
      // the cold start: a short ready-wait that closes and resubscribes
      // can miss `task_stream_ready` for good.
      readyTimeout: const Duration(seconds: 120),
    );
    textToSpeechViewModel = TextToSpeechViewModel(
      sessionService: TextToSpeechSessionService(
        audioSession: widget.audioSession,
        apiClient: _dependencies.apiClient,
        sessionFactory: _dependencies.createSession,
        // The model sends the whole synthesis faster than realtime and the
        // point of this screen is hearing all of it, so the queue holds
        // roughly ten minutes of speech (~240 ms per chunk) instead of the
        // conversation-sized default, where dropping stale audio is right.
        player: QueuedPcmAudioPlayer(
          AudioStreamPcmPlaybackSink(),
          queueCapacityInChunks: 2500,
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
    _dependencies.close();
    super.dispose();
  }

  void _stopActiveSession() {
    if (textToSpeechViewModel.state.sessionState.canStop) {
      unawaited(textToSpeechViewModel.stop());
    }
  }
}
