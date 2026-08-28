import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/layout/project_duration.dart';
import 'package:wiro_realtime/app/layout/project_padding.dart';
import 'package:wiro_realtime/app/theme/app_theme.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/speech_to_speech_view.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_app_bar_title.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb_painter.dart';
import 'package:wiro_realtime/features/speech_to_speech/view_model/speech_to_speech_view_model.dart';

import 'support/fake_conversation_session_controller.dart';

void main() {
  ({
    FakeConversationSessionController controller,
    SpeechToSpeechViewModel viewModel,
  })
  build() {
    final controller = FakeConversationSessionController();
    final viewModel = SpeechToSpeechViewModel(sessionService: controller);
    addTearDown(viewModel.dispose);
    return (controller: controller, viewModel: viewModel);
  }

  /// The orb never stops moving — idle it throbs to invite a tap, live it
  /// pulses — so `pumpAndSettle` only terminates when motion is off. Tests
  /// that need to settle ask for the reduced-motion path, which is a
  /// behaviour worth exercising anyway.
  Future<void> pumpStage(
    WidgetTester tester,
    SpeechToSpeechViewModel viewModel, {
    bool motion = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: !motion),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              ConversationAppBarTitle(viewModel: viewModel),
              // No scroll view, because the screen has none: anything that
              // does not fit here does not fit on a phone either.
              Expanded(
                child: ConversationStageView(viewModel: viewModel),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Taps the orb, which is how a conversation actually begins and the
  /// only thing that earns the connect ring.
  Future<void> tapOrb(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('conversation-orb')));
    await tester.pump();
  }

  testWidgets('ready is a model, a voice, and the orb — no prose', (
    tester,
  ) async {
    final harness = build();

    await pumpStage(tester, harness.viewModel);

    expect(find.text('GPT Realtime Mini'), findsOneWidget);
    expect(find.text('Marin'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('conversation-orb')),
      findsOneWidget,
    );

    // The orb carries the invitation, so nothing on screen explains it.
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .toList();
    expect(rendered, ['GPT Realtime Mini', 'Marin']);
  });

  testWidgets('the orb itself starts the conversation', (tester) async {
    final harness = build();

    await pumpStage(tester, harness.viewModel);
    await tester.tap(find.byKey(const ValueKey<String>('conversation-orb')));
    await tester.pump();

    expect(harness.controller.startCalls, 1);
  });

  testWidgets('the voice is chosen from a dropdown, not thirteen chips', (
    tester,
  ) async {
    final harness = build();

    await pumpStage(tester, harness.viewModel, motion: false);
    // Every option laid out at once was the bulk of the old copy.
    expect(find.text('Cedar'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('field-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('voice-cedar')));
    await tester.pumpAndSettle();

    expect(harness.viewModel.parameters.require('voice').value, 'cedar');
    expect(find.text('Cedar'), findsOneWidget);
  });

  testWidgets('connecting stays on the setup screen and names its step', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);
    await tapOrb(tester);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.creatingTask,
      ),
    );
    await tester.pump();

    // Same panel, same orb: it grows a ring and one line, not a screen.
    expect(find.text('GPT Realtime Mini'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('conversation-orb')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('connect-note')),
      findsOneWidget,
    );
    expect(find.text(ConversationCopy.connecting), findsOneWidget);
    expect(find.text('creatingTask'), findsNothing);
    expect(find.text(ConversationCopy.cancel), findsOneWidget);

    final orb = tester.widget<VoiceOrb>(
      find.byKey(const ValueKey<String>('conversation-orb')),
    );
    expect(orb.mode, VoiceOrbMode.connecting);
    expect(orb.progress, closeTo(0.6, 0.01));
  });

  // The whole point of one orb rather than one panel per stage: the
  // element survives the change, so the change can be animated across.
  testWidgets('the orb is the same element from idle to live', (tester) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);

    final orb = find.byKey(const ValueKey<String>('conversation-orb'));
    final identity = tester.element(orb);

    for (final state in [
      RealtimeSessionState.creatingTask,
      RealtimeSessionState.streaming,
      RealtimeSessionState.stopping,
      RealtimeSessionState.completed,
    ]) {
      harness.controller.publish(
        ConversationSessionSnapshot(
          sessionState: state,
          microphoneActive: true,
        ),
      );
      await tester.pump();
      expect(tester.element(orb), same(identity), reason: '$state');
    }
  });

  testWidgets('every connect step advances the ring and the line', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    double? progressOf() {
      return tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('conversation-orb')),
          )
          .progress;
    }

    // Idle wears no ring: there is nothing yet to be part-way through.
    expect(progressOf(), isNull);

    await tapOrb(tester);

    const steps = <(RealtimeSessionState, String)>[
      (
        RealtimeSessionState.requestingPermission,
        ConversationCopy.connectingPermission,
      ),
      (RealtimeSessionState.preparingAudio, ConversationCopy.connecting),
      (RealtimeSessionState.creatingTask, ConversationCopy.connecting),
      (RealtimeSessionState.connectingSocket, ConversationCopy.connecting),
      (
        RealtimeSessionState.waitingForStream,
        ConversationCopy.connectingStream,
      ),
    ];

    var previous = 0.0;
    for (final (state, caption) in steps) {
      harness.controller.publish(
        ConversationSessionSnapshot(sessionState: state),
      );
      await tester.pump();

      expect(find.text(caption), findsOneWidget, reason: '$state');
      expect(progressOf(), greaterThan(previous), reason: '$state');
      previous = progressOf()!;
    }
    // The last step leaves the ring open: nothing is audible yet.
    expect(previous, inExclusiveRange(0.9, 1));
  });

  // The ring belongs to the wait the line describes. It used to be held
  // on to after it flew off, and since every stage change rewinds the
  // blend it is drawn against, it came back around the live orb each time
  // the floor passed between the two speakers.
  testWidgets('the connect ring does not come back mid-conversation', (
    tester,
  ) async {
    VoiceOrbPainter painterOf() {
      return tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('conversation-orb')),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((paint) => paint.painter)
          .whereType<VoiceOrbPainter>()
          .single;
    }

    final harness = build();
    await pumpStage(tester, harness.viewModel);
    await tapOrb(tester);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.waitingForStream,
      ),
    );
    await tester.pump();
    expect(painterOf().progress, isNotNull);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        microphoneActive: true,
      ),
    );
    await tester.pump();
    await tester.pump(ProjectDuration.stageSwap);
    await tester.pump(ProjectDuration.stageSwap);
    expect(painterOf().progress, isNull);

    // The live orb changing modes, which happens several times a sentence.
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        microphoneActive: true,
        muted: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(painterOf().releasedProgress, isNull);
  });

  testWidgets('the connect line and its cancel leave with the wait', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    expect(
      find.byKey(const ValueKey<String>('connect-note')),
      findsNothing,
    );
    expect(find.text(ConversationCopy.cancel), findsNothing);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.failure,
        errorMessage: 'Could not reach Wiro. Check the network connection.',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('connect-note')),
      findsNothing,
    );
    expect(find.text(ConversationCopy.cancel), findsNothing);
  });

  testWidgets('live renders only the interactive orb', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        elapsed: Duration(seconds: 84),
        userTranscript: 'what is the weather',
        aiTranscript: 'it is clear tonight',
        microphoneActive: true,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('conversation-orb')),
      findsOneWidget,
    );
    expect(find.text('01:24'), findsNothing);
    expect(find.text('You'), findsNothing);
    expect(find.text('Assistant'), findsNothing);
    expect(find.text('what is the weather'), findsNothing);
    expect(find.text('it is clear tonight'), findsNothing);
    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('conversation-orb')),
          )
          .mode,
      VoiceOrbMode.listening,
    );
  });

  testWidgets('the live orb pauses and resumes without ending', (tester) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        microphoneActive: true,
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('conversation-orb')),
          )
          .semanticLabel,
      ConversationCopy.orbPauseSemanticLabel,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('conversation-orb')),
    );
    await tester.pump();
    expect(harness.controller.muteRequests, [true]);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        muted: true,
      ),
    );
    await tester.pump();
    // The orb morphs between modes; the paused icon lands once the
    // crossfade has run.
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('conversation-orb')),
        matching: find.byIcon(Icons.mic_off_rounded),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('conversation-orb')),
          )
          .semanticLabel,
      ConversationCopy.orbResumeSemanticLabel,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('conversation-orb')),
    );
    await tester.pump();

    expect(harness.controller.muteRequests, [true, false]);
    expect(harness.controller.stopCalls, 0);
  });

  testWidgets('tapping the orb while the assistant speaks silences it', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        microphoneActive: true,
      ),
    );
    // One second of queued assistant audio keeps the playhead in the
    // future for the whole test.
    harness.controller.voiceActivity.addAiChunk(Uint8List(48000));
    await tester.pump();

    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('conversation-orb')),
          )
          .semanticLabel,
      ConversationCopy.orbSilenceSemanticLabel,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('conversation-orb')),
    );
    await tester.pump();

    expect(harness.controller.interruptCalls, 1);
    expect(harness.controller.muteRequests, isEmpty);

    // Clears the phase timer so the test ends with nothing armed.
    harness.controller.voiceActivity.reset();
  });

  testWidgets('live exposes the voice pill and forwards a new selection', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        microphoneActive: true,
      ),
    );
    await tester.pump();
    await tester.pump(ProjectDuration.transition);

    final liveVoice = find.descendant(
      of: find.byKey(const ValueKey<String>('live-app-bar-meta')),
      matching: find.byKey(const ValueKey<String>('field-voice')),
    );
    expect(liveVoice, findsOneWidget);
    await tester.tap(liveVoice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cedar'));
    await tester.pump();

    expect(harness.controller.changeVoiceRequests, ['cedar']);
  });

  testWidgets('a voice change reports itself on the pill, not the orb', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
      ),
    );
    await tester.pump();

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.creatingTask,
        isReconfiguring: true,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('live-app-bar-meta')),
      findsOneWidget,
    );
    // The spinner belongs to the control that was touched. The orb keeps
    // the conversation's own look, because the conversation did not stop.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final orb = tester.widget<VoiceOrb>(
      find.byKey(const ValueKey<String>('conversation-orb')),
    );
    expect(orb.progress, isNull);
    expect(orb.mode, VoiceOrbMode.listening);
  });

  // The transport going round again mid-sentence is the app's problem.
  // Ringing the orb and captioning the steps hands it to the speaker,
  // who is talking and did not ask for any of it.
  testWidgets('a dropped connection is rebuilt without a word', (tester) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.streaming,
        elapsed: Duration(seconds: 30),
      ),
    );
    await tester.pumpAndSettle();

    for (final state in [
      RealtimeSessionState.creatingTask,
      RealtimeSessionState.connectingSocket,
      RealtimeSessionState.waitingForStream,
    ]) {
      harness.controller.publish(
        ConversationSessionSnapshot(
          sessionState: state,
          elapsed: const Duration(seconds: 30),
        ),
      );
      await tester.pumpAndSettle();

      final orb = tester.widget<VoiceOrb>(
        find.byKey(const ValueKey<String>('conversation-orb')),
      );
      expect(orb.progress, isNull, reason: '$state');
      expect(orb.mode, VoiceOrbMode.listening, reason: '$state');
      expect(
        find.byKey(const ValueKey<String>('connect-note')),
        findsNothing,
        reason: '$state',
      );
      expect(
        find.text(ConversationCopy.connectingStream),
        findsNothing,
        reason: '$state',
      );
    }
  });

  testWidgets('ending keeps the orb but disables interaction', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.stopping,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('conversation-orb')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('conversation-orb')),
          )
          .semanticLabel,
      isNull,
    );
    expect(harness.controller.muteRequests, isEmpty);
  });

  testWidgets('completed returns to the setup orb without a summary screen', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.completed,
        elapsed: Duration(minutes: 2, seconds: 5),
        userTranscript: 'thanks',
      ),
    );
    await tester.pump();

    expect(find.text('Conversation ended.'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('conversation-orb')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('conversation-orb')));
    await tester.pump();
    expect(harness.controller.startCalls, 1);
  });

  testWidgets('failures keep the setup orb and say what happened once', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.failure,
        errorMessage: 'Could not reach Wiro. Check the network connection.',
        protocolEvents: ['failure:networkUnavailable'],
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('conversation-orb')),
      findsOneWidget,
    );
    expect(
      find.text('Could not reach Wiro. Check the network connection.'),
      findsOneWidget,
    );
    // One line, not a screen: no title, no diagnostics, and nothing to press
    // but the orb, since tapping again is the way out of this one.
    expect(find.text('The conversation stopped.'), findsNothing);
    expect(find.text('failure:networkUnavailable'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('open-settings-control')),
      findsNothing,
    );
  });

  testWidgets('a revoked microphone offers the way out', (tester) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.failure,
        errorMessage: 'Microphone access is disabled. Enable it in settings.',
        canOpenSystemSettings: true,
      ),
    );
    // The note grows into place; it cannot be pressed through the clip
    // until it has.
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('open-settings-control')),
    );
    await tester.pump();

    expect(harness.controller.openSystemSettingsCalls, 1);
  });

  // Nothing broke, so nothing is said: the orb is the whole message.
  testWidgets('an ended conversation returns to a wordless orb', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.completed,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('conversation-orb')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('failure-note')), findsNothing);
  });

  // Nothing on this screen scrolls, so the fullest the screen ever gets —
  // the connect line and its cancel under the orb — has to fit the
  // smallest phone. If it stops fitting there is no rubber-band left to
  // hide it behind.
  testWidgets('the fullest the screen gets fits the smallest phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = build();
    // The real screen, bars and all: what is left for the orb is what the
    // app bar and the navigation bar have not taken.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            title: ConversationAppBarTitle(viewModel: harness.viewModel),
          ),
          body: Padding(
            padding: ProjectPadding.stage,
            child: ConversationStageView(viewModel: harness.viewModel),
          ),
          bottomNavigationBar: const SizedBox(height: 80),
        ),
      ),
    );
    await tapOrb(tester);
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.waitingForStream,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('connect-note')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // The ring answers a tap. A session the service restarts on its own
  // after a server error answers nothing, and ringing the orb for it
  // tells someone who is not waiting that they are.
  testWidgets('a connection nobody asked for is drawn without a ring', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.failure,
        errorMessage: 'Could not reach Wiro. Check the network connection.',
      ),
    );
    await tester.pumpAndSettle();

    // The service picks the conversation back up by itself.
    for (final state in [
      RealtimeSessionState.creatingTask,
      RealtimeSessionState.connectingSocket,
      RealtimeSessionState.waitingForStream,
    ]) {
      harness.controller.publish(ConversationSessionSnapshot(
        sessionState: state,
      ));
      await tester.pumpAndSettle();

      final orb = tester.widget<VoiceOrb>(
        find.byKey(const ValueKey<String>('conversation-orb')),
      );
      expect(orb.progress, isNull, reason: '$state');
      expect(
        find.byKey(const ValueKey<String>('connect-note')),
        findsNothing,
        reason: '$state',
      );
    }

    // Tapping it again is a wait someone chose, and that one is drawn.
    harness.controller.publish(const ConversationSessionSnapshot());
    await tester.pumpAndSettle();
    await tapOrb(tester);
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.creatingTask,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('conversation-orb')),
          )
          .progress,
      isNotNull,
    );
  });

  testWidgets('a healthy session says nothing about failure', (tester) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    // A message left over from an earlier attempt must not outlive it.
    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.creatingTask,
        errorMessage: 'Could not reach Wiro. Check the network connection.',
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('failure-note')), findsNothing);
  });

  testWidgets('voice change keeps the live orb instead of an error screen', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.creatingTask,
        isReconfiguring: true,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('conversation-orb')),
      findsOneWidget,
    );
    expect(find.text('The conversation stopped.'), findsNothing);
  });

  testWidgets('no session state name ever reaches the screen', (tester) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    for (final state in RealtimeSessionState.values) {
      harness.controller.publish(
        ConversationSessionSnapshot(sessionState: state),
      );
      await tester.pumpAndSettle();

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .join(' ');
      expect(rendered, isNot(contains(state.name)), reason: state.name);
    }
  });
}
