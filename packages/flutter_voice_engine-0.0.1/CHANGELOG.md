# Changelog

## 0.0.1+wiro.1

- Do not start recording when the Flutter event stream attaches.
- Start recording only after explicit initialization and start commands.
- Install the recording tap with the input node's current native format.
- Recreate the recording converter when the native input format changes.
- Use voice-chat-compatible Bluetooth and speaker session options.

## 0.0.1 (Unreleased)

- **iOS**:
    - Supports real-time audio recording and playback with hardware-based acoustic echo cancellation (AEC).
    - Provides `initialize`, `startRecording`, `stopRecording`, `playAudioChunk`, `stopPlayback`, `shutdown` methods.
    - Streams Base64-encoded audio chunks (`audioChunkStream`) and errors (`errorStream`).
    - Handles audio interruptions via `onInterruption` callback.
    - Configurable audio settings (`sampleRate`, `channels`, `bitDepth`, `bufferSize`, `amplitudeThreshold`, `enableAEC`).
- **Android**:
    - Not supported in this version.