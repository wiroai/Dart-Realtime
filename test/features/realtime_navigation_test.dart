import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/app/app.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/realtime_home/view/widgets/session_controls.dart';

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
      find.text('mistralai/voxtral-mini-4b-realtime-2602'),
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
