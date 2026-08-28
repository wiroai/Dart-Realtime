import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/app.dart';
import 'package:wiro_realtime/app/widgets/session_controls.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/speech_to_speech_view.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/widgets/voice_orb.dart';
import 'package:wiro_realtime/features/speech_to_text/view/speech_to_text_view.dart';
import 'package:wiro_realtime/features/text_to_speech/view/text_to_speech_view.dart';

void main() {
  testWidgets('navigates to the three realtime destinations', (tester) async {
    // The idle voice orb throbs forever to advertise itself as the button
    // that starts a conversation, and `pumpAndSettle` never returns while
    // it does. Reduced motion parks it.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      const WiroRealtimeApp(
        credentials: WiroCredentials(apiKey: 'example-key'),
      ),
    );

    expect(find.text('Conversation'), findsWidgets);
    expect(find.text('GPT Realtime Mini'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('nav-transcription')));
    await tester.pumpAndSettle();
    expect(find.text('Transcription'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('transcription-mic-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('nav-speech')));
    await tester.pumpAndSettle();
    expect(find.text('Speech'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('tts-model-selector')),
      findsOneWidget,
    );
  });

  testWidgets('reaching the conversation tab creates no session', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      const WiroRealtimeApp(
        credentials: WiroCredentials(apiKey: 'example-key'),
      ),
    );
    await tester.pump();

    // A session is a billed task, so the orb still has to be tapped: it
    // invites a start rather than reporting one already under way.
    expect(
      tester
          .widget<VoiceOrb>(
            find.byKey(const ValueKey<String>('conversation-orb')),
          )
          .semanticLabel,
      ConversationCopy.orbStartSemanticLabel,
    );
  });

  // The destinations stay mounted behind one another, so nothing but this
  // flag tells a conversation that the speaker walked away from it.
  testWidgets('leaving the conversation tab tells it it is off screen', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      const WiroRealtimeApp(
        credentials: WiroCredentials(apiKey: 'example-key'),
      ),
    );
    final conversation = find.byType(SpeechToSpeechView, skipOffstage: false);
    expect(tester.widget<SpeechToSpeechView>(conversation).isVisible, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('nav-transcription')));
    await tester.pumpAndSettle();

    expect(tester.widget<SpeechToSpeechView>(conversation).isVisible, isFalse);
  });

  // The same contract holds for the other two destinations: their sessions
  // are billed tasks too, and only this flag tells them the tab was left.
  testWidgets('every destination is told when it goes off screen', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await tester.pumpWidget(
      const WiroRealtimeApp(
        credentials: WiroCredentials(apiKey: 'example-key'),
      ),
    );
    final transcription = find.byType(SpeechToTextView, skipOffstage: false);
    final speech = find.byType(TextToSpeechView, skipOffstage: false);
    expect(tester.widget<SpeechToTextView>(transcription).isVisible, isFalse);
    expect(tester.widget<TextToSpeechView>(speech).isVisible, isFalse);

    await tester.tap(find.byKey(const ValueKey<String>('nav-transcription')));
    await tester.pumpAndSettle();
    expect(tester.widget<SpeechToTextView>(transcription).isVisible, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('nav-speech')));
    await tester.pumpAndSettle();
    expect(tester.widget<SpeechToTextView>(transcription).isVisible, isFalse);
    expect(tester.widget<TextToSpeechView>(speech).isVisible, isTrue);
  });

  testWidgets('disables start while a session is active', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StartStopControls(
            sessionState: RealtimeSessionState.streaming,
            startLabel: 'Start',
            stopLabel: 'Stop',
            onStart: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('start-control')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey<String>('stop-control')),
          )
          .onPressed,
      isNotNull,
    );
  });
}
