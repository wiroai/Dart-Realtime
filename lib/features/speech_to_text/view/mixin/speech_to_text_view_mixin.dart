import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wiro_realtime/core/audio/pcm_audio_recorder.dart';
import 'package:wiro_realtime/core/audio/record_pcm_capture_source.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_dependencies.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_text/service/speech_to_text_session_service.dart';
import 'package:wiro_realtime/features/speech_to_text/view/speech_to_text_view.dart';
import 'package:wiro_realtime/features/speech_to_text/view_model/speech_to_text_view_model.dart';

mixin SpeechToTextViewMixin on State<SpeechToTextView> {
  late final SpeechToTextViewModel speechToTextViewModel;
  late final RealtimeSessionDependencies _dependencies;
  late final AppLifecycleListener _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    _dependencies = RealtimeSessionDependencies(
      credentials: widget.credentials,
      // The Voxtral worker cold-starts well past the default ready-wait,
      // and the socket replays nothing to a subscriber that arrives
      // after an event fired, so the first subscription has to outlive
      // the spin-up.
      readyTimeout: const Duration(seconds: 120),
    );
    speechToTextViewModel = SpeechToTextViewModel(
      sessionService: SpeechToTextSessionService(
        audioSession: widget.audioSession,
        apiClient: _dependencies.apiClient,
        sessionFactory: _dependencies.createSession,
        recorder: BufferedPcmAudioRecorder(
          RecordPcmCaptureSource(),
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

  /// Leaving the tab is leaving the session: transcription has no idle
  /// conversation to hold open, so an unwatched tab keeping the microphone
  /// hot and the task billing is only a leak.
  @override
  void didUpdateWidget(SpeechToTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible && !widget.isVisible) {
      _stopActiveSession();
    }
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    speechToTextViewModel.dispose();
    _dependencies.close();
    super.dispose();
  }

  void _stopActiveSession() {
    if (speechToTextViewModel.state.sessionState.canStop) {
      unawaited(speechToTextViewModel.stop());
    }
  }
}
