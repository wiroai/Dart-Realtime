enum AudioFailureCode {
  captureUnavailable,
  playbackUnavailable,
}

sealed class AudioFailure implements Exception {
  const AudioFailure({
    required this.code,
    required this.message,
  });

  final AudioFailureCode code;
  final String message;

  @override
  String toString() => message;
}

final class AudioCaptureFailure extends AudioFailure {
  const AudioCaptureFailure()
    : super(
        code: AudioFailureCode.captureUnavailable,
        message: 'Microphone capture could not be started.',
      );
}

final class AudioPlaybackFailure extends AudioFailure {
  const AudioPlaybackFailure()
    : super(
        code: AudioFailureCode.playbackUnavailable,
        message: 'Audio playback could not be started.',
      );
}
