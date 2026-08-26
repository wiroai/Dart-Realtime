import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/layout/project_duration.dart';
import 'package:wiro_realtime/app/theme/app_theme.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_session_snapshot.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_fields.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/speech_to_speech_view.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/advanced_settings_sheet.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/conversation_app_bar_bottom.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb.dart';
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
              ConversationAppBarBottom(viewModel: viewModel),
              Expanded(
                child: SingleChildScrollView(
                  child: ConversationStageSwitcher(viewModel: viewModel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('ready is a model, a voice, and the orb — no prose', (
    tester,
  ) async {
    final harness = build();

    await pumpStage(tester, harness.viewModel);

    expect(find.text('GPT Realtime Mini'), findsOneWidget);
    expect(find.text('Marin'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('start-control')), findsOneWidget);

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
    await tester.tap(find.byKey(const ValueKey<String>('start-control')));
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

  testWidgets('the settings sheet reaches every parameter but the voice', (
    tester,
  ) async {
    final harness = build();
    final model = harness.controller.model;

    // The two halves have to add up: a field dropped from both lists would
    // be unreachable, and one in both would be editable in two places.
    expect(
      [
        ConversationFields.voice(model)!.id,
        ...ConversationFields.advanced(model).map((field) => field.id),
      ]..sort(),
      model.firstPassFields.map((field) => field.id).toList()..sort(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdvancedSettingsSheet(
                context,
                fields: ConversationFields.advanced(model),
                values: harness.viewModel.parameters,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final field in ConversationFields.advanced(model)) {
      expect(
        find.byKey(ValueKey<String>('field-${field.id}')),
        findsOneWidget,
        reason: field.id,
      );
    }
    expect(find.byKey(const ValueKey<String>('field-voice')), findsNothing);
  });

  testWidgets('connecting stays on the setup screen and names the step', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.creatingTask,
      ),
    );
    await tester.pump();

    // Same panel, same orb: only the ring and the step name change.
    expect(find.text('GPT Realtime Mini'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('start-control')), findsOneWidget);
    expect(find.text('Creating session'), findsOneWidget);
    expect(find.text('creatingTask'), findsNothing);
    expect(find.text(ConversationCopy.cancel), findsOneWidget);
  });

  testWidgets('the connecting ring closes as the steps advance', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    double? progressOf() {
      return tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('start-control')),
          )
          .progress;
    }

    expect(progressOf(), isNull);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.requestingPermission,
      ),
    );
    await tester.pump();
    final first = progressOf();

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.waitingForStream,
      ),
    );
    await tester.pump();

    expect(first, isNotNull);
    expect(progressOf(), 1.0);
    expect(progressOf()! > first!, isTrue);
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
      find.byKey(const ValueKey<String>('live-orb-control')),
      findsOneWidget,
    );
    expect(find.text('01:24'), findsNothing);
    expect(find.text(ConversationCopy.speakerYou), findsNothing);
    expect(find.text(ConversationCopy.speakerAssistant), findsNothing);
    expect(find.text('what is the weather'), findsNothing);
    expect(find.text('it is clear tonight'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('live-orb-control')),
        matching: find.byIcon(Icons.mic_rounded),
      ),
      findsOneWidget,
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
            find.byKey(const ValueKey<String>('live-orb-control')),
          )
          .semanticLabel,
      ConversationCopy.orbPauseSemanticLabel,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('live-orb-control')),
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
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('live-orb-control')),
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('live-orb-control')),
          )
          .semanticLabel,
      ConversationCopy.orbResumeSemanticLabel,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('live-orb-control')),
    );
    await tester.pump();

    expect(harness.controller.muteRequests, [true, false]);
    expect(harness.controller.speakerRequests, isEmpty);
    expect(harness.controller.stopCalls, 0);
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

  testWidgets('voice changes keep the live orb in a connecting animation', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.creatingTask,
        isChangingVoice: true,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('live-app-bar-meta')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('live-orb-control')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('live-orb-control')),
          )
          .progress,
      closeTo(1 / 3, 0.01),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
      find.byKey(const ValueKey<String>('live-orb-control')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('live-orb-control')),
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

    expect(find.text(ConversationCopy.summaryTitle), findsNothing);
    expect(find.byKey(const ValueKey<String>('start-control')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('start-control')));
    await tester.pump();
    expect(harness.controller.startCalls, 1);
  });

  testWidgets('failures keep the setup orb without a dedicated error screen', (
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

    expect(find.byKey(const ValueKey<String>('start-control')), findsOneWidget);
    expect(find.text(ConversationCopy.failureTitle), findsNothing);
    expect(find.text('failure:networkUnavailable'), findsNothing);
  });

  testWidgets('voice change keeps the live orb instead of an error screen', (
    tester,
  ) async {
    final harness = build();
    await pumpStage(tester, harness.viewModel, motion: false);

    harness.controller.publish(
      const ConversationSessionSnapshot(
        sessionState: RealtimeSessionState.creatingTask,
        isChangingVoice: true,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('live-orb-control')),
      findsOneWidget,
    );
    expect(find.text(ConversationCopy.failureTitle), findsNothing);
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
