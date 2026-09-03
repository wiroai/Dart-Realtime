<div align="center">

<img src="https://wiro.ai/images/logos/logo/logo.png" alt="Wiro" width="180" />

# Wiro Realtime for Flutter

**Official Flutter example for live voice AI on [Wiro](https://wiro.ai) —
speech-to-speech conversation, realtime transcription, and text-to-speech**

[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13%2B-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS-3DDC84?style=for-the-badge)](#requirements)
[![MIT](https://img.shields.io/badge/license-MIT-6f42c1?style=for-the-badge)](LICENSE)

[Docs](https://wiro.ai/docs) · [Models](https://wiro.ai/models) · [Dashboard](https://wiro.ai/panel) · [Create Project](https://wiro.ai/panel/project/new)

</div>

## What's inside

Three realtime audio flows, each a tab in the app, each backed by a live
Wiro model over one WebSocket protocol:

| Flow | Model | What it does |
| --- | --- | --- |
| 🎙️ Conversation | [`openai/gpt-realtime-mini`](https://wiro.ai/models) | Full-duplex voice chat with barge-in |
| 📝 Transcription | [`mistralai/voxtral-mini-4b-realtime-2602`](https://wiro.ai/models) | Live speech-to-text as you talk |
| 🔊 Speech | [`openmoss/moss-tts-realtime`](https://wiro.ai/models) | Streaming text-to-speech playback |

<div align="center">
<table>
  <tr>
    <td align="center"><b>Conversation</b></td>
    <td align="center"><b>Transcription</b></td>
    <td align="center"><b>Speech</b></td>
  </tr>
  <tr>
    <td><img src="docs/images/conversation.png" width="260" alt="Speech-to-speech conversation" /></td>
    <td><img src="docs/images/transcription.png" width="260" alt="Realtime transcription" /></td>
    <td><img src="docs/images/speech.png" width="260" alt="Text-to-speech" /></td>
  </tr>
</table>
</div>

## Features

- Live speech-to-speech conversation with voice activity detection,
  barge-in, and a noise gate
- Realtime microphone transcription with streaming partial results
- Streaming text-to-speech with bounded PCM playback
- One native audio graph for capture and playback, so the OS echo
  canceller (AEC) actually works — see
  [`packages/wiro_voice_engine`](packages/wiro_voice_engine)
- Signed REST Run requests and the full Wiro realtime WebSocket protocol
- Bounded capture/playback queues, safe PCM overflow shedding, audio
  route and interruption handling
- Cross-feature guard so two tabs never hold the microphone at once
- Automatic reconnect to the same task on socket drops, with a bounded
  restart budget
- Session lifecycle fully covered by tests — no device needed to verify
  the plumbing

## Requirements

- Flutter stable with Dart `3.13.1` or newer
- A **physical** Android or iOS device — simulators have no usable
  microphone path
- A [Wiro project and API key](https://wiro.ai/panel/project/new)

The iOS project uses Swift Package Manager — there is no Podfile and no
CocoaPods setup to run. Use a Flutter version with SPM support enabled.
The project ships without a signing team: open `ios/Runner.xcworkspace`
once and pick yours under **Runner → Signing & Capabilities** before the
first device run.

## Run

```sh
flutter pub get
flutter run --dart-define=WIRO_API_KEY=YOUR_API_KEY
```

For signature-based Wiro projects, also pass the secret:

```sh
flutter run \
  --dart-define=WIRO_API_KEY=YOUR_API_KEY \
  --dart-define=WIRO_API_SECRET=YOUR_API_SECRET
```

Leave `WIRO_API_SECRET` out for API-key-only projects. The app fails
before `runApp` when `WIRO_API_KEY` is missing.

> **Credentials warning:** values supplied through `--dart-define` are
> compiled into the binary and are for local development only. Never
> distribute builds containing real credentials — production apps should
> authenticate through a controlled backend or a short-lived credential
> flow.

## Make it yours

[`lib/app/config/conversation_config.dart`](lib/app/config/conversation_config.dart)
holds the persona, the voice, the model, and the session time limit.
Editing that one file is the whole of turning this example into a
product.

```dart
static const String persona = '...who the assistant is...';
static const String voice = 'marin';
static const Duration maxSessionDuration = Duration(minutes: 10);
```

Common changes:

- **Give the assistant a job** — rewrite `persona`.
- **Change the voice** — set `voice` to any option the model catalog
  lists.
- **Tune the engineering parameters** — `parameters` overrides the
  catalog defaults for turn detection, audio formats, and rates.
- **Ship only the conversation** — delete
  `lib/features/speech_to_text/` and `lib/features/text_to_speech/`
  (plus their `test/features/` folders), then remove the two
  `NavigationDestination`s from
  `lib/features/realtime_home/view/realtime_home_view.dart`. `core/` is
  untouched.

## How a conversation runs

```text
REST:      https://api.wiro.ai/v1
WebSocket: wss://socket.wiro.ai/v1
Run:       POST /Run/{owner}/{model}
```

1. `POST /Run/{owner}/{model}` returns a task id and a task token.
2. A WebSocket opens and subscribes with
   `{ "type": "task_info", "tasktoken": "..." }`.
3. After `task_stream_ready`, 20 ms PCM chunks stream up as
   `UTF8(tasktoken + "|") + pcm_bytes`; audio and transcripts stream
   back.
4. `task_session_end` closes the session — sent by the app on leave, or
   by the server at the time limit.

Audio is signed 16-bit PCM, 24 kHz, mono, little-endian on both sides.

Authentication is `x-api-key` alone, or `x-api-key` + `x-nonce` +
`x-signature` where the signature is
`HMAC-SHA256(key = API_KEY, message = API_SECRET + NONCE)`.

## Project layout

```text
lib/
 app/       shell, theme, layout tokens, config, shared widgets
 core/      reusable Wiro plumbing — auth, network, realtime, audio
 features/  one folder per tab: view/, view_model/, service/
packages/
 wiro_voice_engine/  native AEC audio bridge (AVAudioEngine / AudioRecord)
```

`core/` has no dependency on any feature and covers the whole Wiro
integration — it is the part worth lifting into your own app.

## Tests

```sh
flutter analyze
flutter test
```

Tests mirror `lib/` and ship fakes for audio, network, and the socket,
so the entire session lifecycle runs without a device. CI runs the same
two commands, plus `flutter analyze` for `packages/wiro_voice_engine`,
on every push and pull request.

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull request.
Security problems go to [`SECURITY.md`](SECURITY.md), not to a public
issue.

## Documentation

- [Wiro documentation](https://wiro.ai/docs)
- [Available models](https://wiro.ai/models)
- [Dart SDK — Wiro QuickStart](https://github.com/wiroai/Dart-QuickStart)
- [Kotlin counterpart](https://github.com/wiroai/Kotlin-Realtime)
- [Swift counterpart](https://github.com/wiroai/Swift-Realtime)
- [React Native counterpart](https://github.com/wiroai/ReactNative-Realtime)

## License

MIT

---

<div align="center">

<img src="https://wiro.ai/images/koala/accent-heavy-koala.png" alt="Wiro" width="80" />

**Built with 💚 by the Wiro team**

[wiro.ai](https://wiro.ai) · [GitHub @wiroai](https://github.com/wiroai)

</div>
