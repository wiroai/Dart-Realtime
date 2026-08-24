import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wiro_realtime/core/audio/realtime_audio_session.dart';

final class PluginRealtimeAudioSession implements RealtimeAudioSession {
  final StreamController<RealtimeAudioInterruption> _interruptionController =
      StreamController<RealtimeAudioInterruption>.broadcast(sync: true);
  final StreamController<void> _becomingNoisyController =
      StreamController<void>.broadcast(sync: true);
  final StreamController<void> _routeChangesController =
      StreamController<void>.broadcast(sync: true);

  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;
  StreamSubscription<AudioDevicesChangedEvent>? _routeSubscription;
  bool _eventsBound = false;
  bool _disposed = false;

  @override
  Stream<RealtimeAudioInterruption> get interruptions =>
      _interruptionController.stream;

  @override
  Stream<void> get becomingNoisy => _becomingNoisyController.stream;

  @override
  Stream<void> get routeChanges => _routeChangesController.stream;

  @override
  Future<AudioPreparationResult> prepare(
    RealtimeAudioProfile profile,
  ) async {
    try {
      if (_disposed) {
        return AudioPreparationResult.unavailable;
      }
      if (profile.requiresMicrophone) {
        final permissionResult = await _requestMicrophonePermission();
        if (permissionResult != AudioPreparationResult.ready) {
          return permissionResult;
        }
      }

      final session = await AudioSession.instance;
      _session = session;
      _bindEvents(session);
      await session.configure(_configurationFor(profile));

      final active = await session.setActive(true);
      return active
          ? AudioPreparationResult.ready
          : AudioPreparationResult.activationDenied;
    } on Object {
      return AudioPreparationResult.unavailable;
    }
  }

  @override
  Future<void> deactivate() async {
    try {
      await _session?.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } on Object {
      // Deactivation is best effort during stop and widget disposal.
    }
  }

  @override
  Future<bool> setSpeakerEnabled({required bool enabled}) async {
    try {
      if (kIsWeb) {
        return true;
      }
      if (Platform.isIOS) {
        await AVAudioSession().overrideOutputAudioPort(
          enabled
              ? AVAudioSessionPortOverride.speaker
              : AVAudioSessionPortOverride.none,
        );
      } else if (Platform.isAndroid) {
        await AndroidAudioManager().setSpeakerphoneOn(enabled);
      }
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await deactivate();
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    await _routeSubscription?.cancel();
    await _interruptionController.close();
    await _becomingNoisyController.close();
    await _routeChangesController.close();
  }

  void _bindEvents(AudioSession session) {
    if (_eventsBound) {
      return;
    }
    _eventsBound = true;
    _interruptionSubscription = session.interruptionEventStream.listen(
      (event) {
        if (!_interruptionController.isClosed) {
          _interruptionController.add(
            event.begin
                ? RealtimeAudioInterruption.began
                : RealtimeAudioInterruption.ended,
          );
        }
      },
    );
    _becomingNoisySubscription = session.becomingNoisyEventStream.listen(
      (_) {
        if (!_becomingNoisyController.isClosed) {
          _becomingNoisyController.add(null);
        }
      },
    );
    _routeSubscription = session.devicesChangedEventStream.listen((_) {
      if (!_routeChangesController.isClosed) {
        _routeChangesController.add(null);
      }
    });
  }

  Future<AudioPreparationResult> _requestMicrophonePermission() async {
    var status = await Permission.microphone.status;
    if (status.isDenied) {
      status = await Permission.microphone.request();
    }

    if (status.isGranted) {
      return AudioPreparationResult.ready;
    }
    if (status.isPermanentlyDenied) {
      return AudioPreparationResult.permissionPermanentlyDenied;
    }
    if (status.isRestricted) {
      return AudioPreparationResult.permissionRestricted;
    }
    return AudioPreparationResult.permissionDenied;
  }

  AudioSessionConfiguration _configurationFor(
    RealtimeAudioProfile profile,
  ) {
    return switch (profile) {
      RealtimeAudioProfile.conversation => AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidWillPauseWhenDucked: true,
      ),
      RealtimeAudioProfile.transcription => const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.record,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.measurement,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidWillPauseWhenDucked: true,
      ),
      RealtimeAudioProfile.speech => AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetoothA2dp |
            AVAudioSessionCategoryOptions.allowAirPlay,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidWillPauseWhenDucked: true,
      ),
    };
  }
}
