# Wiro Realtime for Flutter

Official Wiro example for three realtime audio flows on Android and iOS:

- Conversation: speech-to-speech (`openai/gpt-realtime-mini`)
- Transcription: speech-to-text (`mistralai/voxtral-mini-4b-realtime-2602`)
- Speech: text-to-speech (`openmoss/moss-tts-realtime`, `openbmb/voxcpm2`)

## Make it yours

`lib/app/config/conversation_config.dart` holds the persona, the voice, the
model and the session time limit. Editing that file is the whole of turning
this example into a product. `AGENTS.md` maps the rest of the repository for
coding agents.

## Credentials

Credentials supplied through `--dart-define` are for local development only.
They are compiled into the application binary. Do not distribute builds that
contain real credentials. Production apps should authenticate through a
controlled backend or short-lived credential flow.

This repository includes authenticated REST Run requests, the realtime
WebSocket protocol, bounded PCM capture/playback primitives, and the complete
GPT Realtime Mini conversation, Voxtral transcription, and MOSS
text-to-speech flows. It also includes bounded transport timeouts, cross-feature
single-session protection, audio interruption and route handling, safe PCM
overflow shedding, sanitized failure codes, and profile counters. Android and
iPhone physical-device profiling remains pending; VoxCPM2 stays deferred until
MOSS passes physical-device playback acceptance.

## Schema snapshot

Verified against Wiro MCP `search_docs` and `get_model_schema` on
**2026-08-21**. No paid model run was started during research.

| Example | Model | First-pass fields |
|---|---|---|
| Conversation | `openai/gpt-realtime-mini` | `voice`, `system_instructions`, `transcription_model`, `input_audio_format`, `output_audio_format`, `input_audio_rate`, `output_audio_rate`, `turn_detection_threshold`, `turn_detection_silence_ms` |
| Transcription | `mistralai/voxtral-mini-4b-realtime-2602` | `transcriptionDelay` (`balanced` default) |
| Speech | `openmoss/moss-tts-realtime` | `text` only |
| Speech | `openbmb/voxcpm2` | `prompt`, `cfgValue`, `inferenceSteps` |

### Differences from the original implementation notes

- Audio format select values are `audio/pcm`, `audio/pcmu`, and `audio/pcma`.
- Sample-rate select values are the strings `24000` and `8000`.
- `openbmb/voxcpm2` also exposes `inputAudio`, `inputAudio2`, and
  `promptAudioText`. Those stay out of the first working TTS pass.
- MCP `get_model_schema` marked `cfgValue` required without a default. The
  live model page default is `2.0`; `inferenceSteps` default is `10`.
- MCP docs do not specify signature encoding. The official model pages use
  `openssl dgst -sha256 -hmac`, which is lowercase hex.
- Many API failures return HTTP 200 with `result: false`. Auth failures
  return HTTP 401.
- PCM sample endianness is not documented. This example will treat PCM as
  little-endian until a physical-device stream confirms it.

## Protocol

```text
REST:      https://api.wiro.ai/v1
WebSocket: wss://socket.wiro.ai/v1
Run:       POST /Run/{owner}/{model}
```

Subscribe after Run:

```json
{ "type": "task_info", "tasktoken": "TASK_TOKEN" }
```

Wait for `task_stream_ready` before sending microphone PCM.

End:

```json
{ "type": "task_session_end", "tasktoken": "TASK_TOKEN" }
```

Audio wire format: PCM signed Int16, 24 kHz, mono. Binary frame is
`UTF8(tasktoken + "|") + pcm_bytes`. Capture chunks are 20 ms (480 samples,
960 bytes before the prefix).

Authentication:

- API-key-only: `x-api-key`
- Signature: `x-api-key`, `x-nonce`, `x-signature` where
  `HMAC-SHA256(key=API_KEY, message=API_SECRET + NONCE)`

Leave `WIRO_API_SECRET` empty for API-key-only projects.

## Run

Physical devices are required for microphone and playback acceptance.
Simulator audio is not an acceptance criterion.

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=WIRO_API_KEY=YOUR_API_KEY
```

`WIRO_API_KEY` is required. The app fails before `runApp` when it is missing.

For signature-based projects, also provide the secret:

```sh
flutter run \
  --dart-define=WIRO_API_KEY=YOUR_API_KEY \
  --dart-define=WIRO_API_SECRET=YOUR_API_SECRET
```

Do not provide `WIRO_API_SECRET` for API-key-only projects.

## Tests

```sh
flutter test
```
