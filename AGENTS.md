# AGENTS.md

A Flutter app that holds a live voice conversation with a model running on
Wiro. Clone it, put your own prompt in one file, ship it.

## The one file to edit

`lib/app/config/conversation_config.dart` holds the persona, the voice, the
model and the session time limit. Turning this example into a product is
editing that file. Nothing else has to change.

The model catalog (`lib/core/models/wiro_model_catalog.dart`) describes what
each Wiro model accepts. It is a schema, not a place for product decisions —
config values win over its defaults.

## Run it

```sh
flutter pub get
flutter run --dart-define=WIRO_API_KEY=YOUR_API_KEY
```

Add `--dart-define=WIRO_API_SECRET=...` only for signature-based Wiro
projects. Credentials are never committed and never written to disk. A
physical device is required: simulators have no usable microphone path.

## Layout

```
lib/
  app/       shell, theme, layout tokens, config, shared widgets
  core/      reusable Wiro plumbing — auth, network, realtime, audio, models
  features/  one folder per screen: view/, view_model/, service/
```

`core/` is the part worth stealing. It has no dependency on any feature and
covers the whole integration: signed REST Run requests, the realtime
WebSocket, binary PCM framing, bounded capture and playback queues, echo
cancellation, a noise gate, and a guard that stops two features from opening
the microphone at once.

## How a conversation runs

1. `POST /Run/{owner}/{model}` with the config values returns a task id and
   a task token (`RealtimeTaskLauncher`).
2. A WebSocket opens to `wss://socket.wiro.ai/v1` and subscribes with
   `task_info` (`RealtimeSession`).
3. Once `task_stream_ready` arrives, 20 ms PCM chunks stream up as
   `UTF8(tasktoken + "|") + pcm_bytes`; audio and transcripts stream back.
4. `task_session_end` closes it. Hitting the time limit, or leaving and not
   coming back, both end the task this way.

Wiro charges a realtime task for as long as it is up, and stops one that has
gone quiet so that it stops charging. The app takes the same side. Leaving
the screen ends the conversation, a task the server winds down is not quietly
replaced with another, and `ConversationConfig.suspendGracePeriod` — zero by
default — is the dial for holding a task open for someone who might come
straight back.

A dropped socket is the one case worth fighting for, because the speaker is
still there mid-sentence. The session resubscribes to the task it already has
and only launches a new one once that is refused, since a new task is a new
assistant with no memory of anything said so far. The fight is finite:
`maxAutoRestarts` bounds the restarts a failing backend gets, and once the
budget is spent the orb comes back to be tapped. An orb reconnecting on its
own and failing is indistinguishable from one that is listening, so it is
worth less than a tap. A restart that reaches a live conversation refills
the budget.

Nothing on the way out may wait forever, either. Ending a conversation plays
out whatever audio is already queued, but a sink that stopped draining —
an engine torn down under a route change, a task the server just ended —
would never finish, and the screen would keep showing a live conversation
long after the microphone had stopped. `PcmAudioPlayer.complete` is bounded
for that reason and gives up the tail rather than the screen.

Audio is signed 16-bit PCM, 24 kHz, mono, little-endian, on both sides
(`AudioConstants`). Changing the rate means changing it in the request and
in the local pipeline together, or the audio is garbled.

## Common changes

**Give the assistant a job.** Rewrite `ConversationConfig.persona`. Keep the
two sentences about language unless you want a single-language product.

**Change the voice.** `ConversationConfig.voice`; the accepted values are the
`voice` field options in the catalog.

**Drop the other two features.** This app also ships transcription and
text-to-speech tabs. Delete `lib/features/speech_to_text/`,
`lib/features/text_to_speech/` and their `test/features/` folders, then
remove the two views and the two `NavigationDestination`s from
`lib/features/realtime_home/view/realtime_home_view.dart`. `core/` is
untouched by this.

**Do not auto-start a session.** A session is a billed task, so it begins
when the orb is tapped. Starting one in `initState` bills people for
reaching a screen.

**Do not let a session run off screen.** `SpeechToSpeechView.isVisible` is
what tells the conversation it was left; without it the destinations stay
mounted and an unwatched tab keeps the microphone open and the task billing.
A new screen that hosts the conversation has to pass that flag too.

## Conventions

- State lives in `ValueNotifier`; only the widget that draws a value is
 wrapped in `ValueListenableBuilder` (or `ValueSelectorBuilder`).
- The conversation is one `ConversationOrb` that every stage dresses
 differently, never a panel per stage. A widget swapped out cannot be
 animated across the swap, and the orb settling into a live session is
 the screen's whole story. Do not reintroduce per-stage panels.
- Feature-first folders. A feature owns its `view/`, `view_model/` and
  `service/`. Shared plumbing goes to `core/`; widgets that more than one
  feature draws go to `app/widgets/`. No feature imports another, except
  the home shell mounting the three destinations.
- Services never touch view state. They publish immutable snapshots, which
  is why the whole session lifecycle is testable without a widget tree.
- Styling comes from `context.theme`, `context.textTheme`,
  `context.colorScheme`; spacing from `ProjectPadding` and `ProjectSpacing`;
  sizes from `context.dynamicHeight(...)` and `context.dynamicWidth(...)`.
- The conversation screen carries itself without prose, with two
 exceptions. A failure states what happened in a single line, and a
 permanently denied microphone also gets a way into system settings — a
 silent dead orb is a dead end. And the wait after the orb is tapped
 names the step it is on while a ring closes around the orb, because that
 wait runs on someone else's network and motion alone cannot tell
 "coming" from "stuck". A conversation that merely ended says nothing,
 because the orb coming back already says it.
- The ring and that line answer a tap and nothing else. The view model's
  `start` raises `reportsConnecting` on the state, and the next snapshots
  lower it once the conversation is audible or turns out never to be —
  no widget holds this in a `setState` of its own. Every other
  pass through `connecting` — a dropped socket, an edited voice, a return
  from the background, a session the service restarts on its own after a
  server error — is drawn as the live conversation it is. Keying this to
  the tap rather than to a session state is the point: nobody is waiting
  on those, and a ring tells them their conversation stopped.
- `const` wherever possible, 80-column lines, trailing commas.
- Comments explain why, never what. No comment restates the line below it.

## Before committing

```sh
flutter analyze
flutter test
```

Both must be clean. Tests live in `test/` mirroring `lib/`; each feature has
a `support/` folder with fakes for audio, network and the socket, so a new
test rarely needs new scaffolding.
