enum RealtimeAudioProfile {
  conversation(requiresMicrophone: true),
  transcription(requiresMicrophone: true),
  speech(requiresMicrophone: false);

  const RealtimeAudioProfile({required this.requiresMicrophone});

  final bool requiresMicrophone;
}

enum AudioPreparationResult {
  ready,
  permissionDenied,
  permissionPermanentlyDenied,
  permissionRestricted,
  activationDenied,
  unavailable,
}

enum RealtimeAudioInterruption {
  began,
  ended,
}

extension AudioPreparationResultX on AudioPreparationResult {
  /// True when tapping again can never help and only the system settings
  /// screen can, which is the one failure the app has to offer a way out of.
  bool get needsSystemSettings =>
      this == AudioPreparationResult.permissionPermanentlyDenied;

  String? get errorMessage {
    return switch (this) {
      AudioPreparationResult.ready => null,
      AudioPreparationResult.permissionDenied =>
        'Microphone permission was denied. Allow access and try again.',
      AudioPreparationResult.permissionPermanentlyDenied =>
        'Microphone access is disabled. Enable it in system settings.',
      AudioPreparationResult.permissionRestricted =>
        'Microphone access is restricted on this device.',
      AudioPreparationResult.activationDenied =>
        'The audio session could not be activated. Try again.',
      AudioPreparationResult.unavailable =>
        'The audio session could not be prepared. Try again.',
    };
  }
}

abstract interface class RealtimeAudioSession {
  Stream<RealtimeAudioInterruption> get interruptions;

  Stream<void> get becomingNoisy;

  Stream<void> get routeChanges;

  Future<AudioPreparationResult> prepare(RealtimeAudioProfile profile);

  Future<void> deactivate();

  Future<bool> setSpeakerEnabled({required bool enabled});

  /// Opens the system settings page for this app. Returns false when the
  /// platform refused, which leaves the caller nothing further to offer.
  Future<bool> openSystemSettings();

  Future<void> dispose();
}
