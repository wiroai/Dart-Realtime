import 'package:flutter/material.dart';
import 'package:wiro_realtime/app/extensions/theme_extension.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/features/realtime_home/view/mixin/realtime_home_view_mixin.dart';
import 'package:wiro_realtime/features/realtime_home/view_model/state/realtime_home_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/speech_to_speech_view.dart';
import 'package:wiro_realtime/features/speech_to_text/view/speech_to_text_view.dart';
import 'package:wiro_realtime/features/text_to_speech/view/text_to_speech_view.dart';

class RealtimeHomeView extends StatefulWidget {
  const RealtimeHomeView({required this.credentials, super.key});

  final WiroCredentials credentials;

  @override
  State<RealtimeHomeView> createState() => _RealtimeHomeViewState();
}

class _RealtimeHomeViewState extends State<RealtimeHomeView>
    with RealtimeHomeViewMixin {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RealtimeHomeState>(
      valueListenable: realtimeHomeViewModel,
      builder: (context, state, _) {
        // With the keyboard up the bar would ride on top of it and eat
        // another row of the already-squeezed screen; nobody switches
        // tabs mid-typing, so it steps aside until the keyboard goes.
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        return Scaffold(
          // Consuming the inset here would hide the keyboard from the
          // destinations, and the speech editor rearranges itself around
          // it. Each destination's own scaffold does the resizing; the
          // bar below steps aside so their bottom edge is the screen's.
          resizeToAvoidBottomInset: false,
          // No shared bar: each destination supplies its own sliver bar so
          // it can own its title and its actions.
          body: IndexedStack(
            index: state.selectedIndex,
            children: [
              SpeechToSpeechView(
                credentials: widget.credentials,
                audioSession: realtimeAudioSession,
                sessionGuard: realtimeSessionGuard,
                isVisible: state.selectedIndex == 0,
              ),
              SpeechToTextView(
                credentials: widget.credentials,
                audioSession: realtimeAudioSession,
                sessionGuard: realtimeSessionGuard,
                isVisible: state.selectedIndex == 1,
              ),
              TextToSpeechView(
                credentials: widget.credentials,
                audioSession: realtimeAudioSession,
                sessionGuard: realtimeSessionGuard,
                isVisible: state.selectedIndex == 2,
              ),
            ],
          ),
          // The hairline is the only thing the themed `NavigationBar`
          // cannot draw for itself.
          bottomNavigationBar: keyboardOpen
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: context.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: NavigationBar(
                    selectedIndex: state.selectedIndex,
                    onDestinationSelected:
                        realtimeHomeViewModel.selectDestination,
                    destinations: const [
                      NavigationDestination(
                        key: ValueKey<String>('nav-conversation'),
                        icon: Icon(Icons.forum_outlined),
                        selectedIcon: Icon(Icons.forum),
                        label: 'Conversation',
                      ),
                      NavigationDestination(
                        key: ValueKey<String>('nav-transcription'),
                        icon: Icon(Icons.mic_outlined),
                        selectedIcon: Icon(Icons.mic),
                        label: 'Transcription',
                      ),
                      NavigationDestination(
                        key: ValueKey<String>('nav-speech'),
                        icon: Icon(Icons.record_voice_over_outlined),
                        selectedIcon: Icon(Icons.record_voice_over),
                        label: 'Speech',
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
