# Contributing

Thanks for taking the time. This is a small, opinionated example
app; the bar for a change is that it keeps the example small and
opinionated.

## Before you start

- Read the [README](README.md) end to end. "How a conversation
  runs" and "Project layout" are the architecture document: the
  layer rules, the chrome rules, and the reasons behind the session
  lifecycle. Pull requests that contradict them will be asked to
  change.
- Open an issue first for anything that adds a screen, a
  dependency, or a new layer. Bug fixes and test improvements can go
  straight to a pull request.

## Setup

```sh
flutter pub get
```

The test suite does not talk to Wiro and needs no `--dart-define`.
A physical Android or iOS phone is needed only to hear audio — the
emulator and the simulator have no usable microphone path.

## Running the checks

```sh
flutter analyze
flutter test
cd packages/wiro_voice_engine && flutter pub get && flutter analyze
```

CI runs the same commands for the app and for the
`wiro_voice_engine` package.

## What a good change looks like

- `lib/core/` never imports a feature or a widget. Session services
  never touch widget state; they publish values that widgets listen
  to. Features never import each other.
- Anything that waits on time takes a clock or a duration and is
  tested with `fakeAsync` or a fake clock, not with a real delay in
  the test.
- Native audio stays in `packages/wiro_voice_engine`. The plugin
  moves PCM bytes and owns the platform audio session; decisions
  about the conversation live in Dart where they can be tested.
- Comments explain why, never what. No comment restates the line
  below it.
- 80 columns, trailing commas, `const` where it can be. Theme
  colours and text styles come from the `ThemeData`, not literals.
- Tests live in `test/` mirroring `lib/`. Reuse the fakes under each
  `support/` folder before writing a new one.

## Commit messages

One change per commit, imperative subject under 72 characters, and
a body that says why when the diff does not.

## Reporting a problem

Include the platform and OS version, the device, the model slug
from `lib/app/config/conversation_config.dart`, and the
`flutter run` console output
around the failure. A recording of what you heard is worth more
than a paragraph about it. Never paste an API key or a task token.
