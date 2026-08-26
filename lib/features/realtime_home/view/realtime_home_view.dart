import 'package:flutter/material.dart';
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
        return Scaffold(
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
          bottomNavigationBar: NavigationBar(
            selectedIndex: state.selectedIndex,
            onDestinationSelected: realtimeHomeViewModel.selectDestination,
            destinations: const [
              NavigationDestination(
                key: ValueKey<String>('nav-conversation'),
                icon: Icon(Icons.forum_outlined),
                label: 'Conversation',
              ),
              NavigationDestination(
                key: ValueKey<String>('nav-transcription'),
                icon: Icon(Icons.mic_outlined),
                label: 'Transcription',
              ),
              NavigationDestination(
                key: ValueKey<String>('nav-speech'),
                icon: Icon(Icons.record_voice_over_outlined),
                label: 'Speech',
              ),
            ],
          ),
        );
      },
    );
  }
}
