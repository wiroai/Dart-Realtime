import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wiro_realtime/core/audio/plugin_realtime_audio_session.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_guard.dart';
import 'package:wiro_realtime/features/realtime_home/view/realtime_home_view.dart';
import 'package:wiro_realtime/features/realtime_home/view_model/realtime_home_view_model.dart';

mixin RealtimeHomeViewMixin on State<RealtimeHomeView> {
  late final RealtimeHomeViewModel realtimeHomeViewModel;
  late final RealtimeAudioSession realtimeAudioSession;
  late final RealtimeSessionGuard realtimeSessionGuard;
  late final AppLifecycleListener appLifecycleListener;

  @override
  void initState() {
    super.initState();
    realtimeHomeViewModel = RealtimeHomeViewModel();
    realtimeAudioSession = PluginRealtimeAudioSession();
    realtimeSessionGuard = RealtimeSessionGuard();
    appLifecycleListener = AppLifecycleListener(
      onHide: _deactivateAudio,
      onPause: _deactivateAudio,
      onDetach: _deactivateAudio,
    );
  }

  @override
  void dispose() {
    appLifecycleListener.dispose();
    unawaited(realtimeAudioSession.dispose());
    realtimeSessionGuard.dispose();
    realtimeHomeViewModel.dispose();
    super.dispose();
  }

  void _deactivateAudio() {
    unawaited(realtimeAudioSession.deactivate());
  }
}
