import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/constants/conversation_copy.dart';
import 'package:wiro_realtime/features/speech_to_speech/view/types/conversation_stage.dart';

void main() {
  test('maps every session state onto a stage', () {
    const expected = <RealtimeSessionState, ConversationStage>{
      RealtimeSessionState.idle: ConversationStage.ready,
      RealtimeSessionState.requestingPermission: ConversationStage.connecting,
      RealtimeSessionState.preparingAudio: ConversationStage.connecting,
      RealtimeSessionState.creatingTask: ConversationStage.connecting,
      RealtimeSessionState.connectingSocket: ConversationStage.connecting,
      RealtimeSessionState.waitingForStream: ConversationStage.connecting,
      RealtimeSessionState.streaming: ConversationStage.live,
      RealtimeSessionState.stopping: ConversationStage.ending,
      RealtimeSessionState.completed: ConversationStage.ready,
      RealtimeSessionState.failure: ConversationStage.failed,
    };

    expect(expected.keys, containsAll(RealtimeSessionState.values));
    for (final entry in expected.entries) {
      expect(entry.key.conversationStage, entry.value, reason: '${entry.key}');
    }
  });

  test('numbers the connecting sequence without gaps', () {
    final steps =
        RealtimeSessionState.values
            .map((state) => state.connectingStep)
            .whereType<int>()
            .toList()
          ..sort();

    expect(
      steps,
      List<int>.generate(
        ConversationStagePresentation.connectingStepCount,
        (index) => index + 1,
      ),
    );
  });

  test('numbers only the states that are part of connecting', () {
    for (final state in RealtimeSessionState.values) {
      expect(
        state.connectingStep != null,
        state.conversationStage == ConversationStage.connecting,
        reason: '$state',
      );
    }
  });

  test('labels every connecting state and nothing else', () {
    for (final state in RealtimeSessionState.values) {
      final label = ConversationCopy.connectingStepLabel(state);
      expect(
        label.isNotEmpty,
        state.conversationStage == ConversationStage.connecting,
        reason: '$state',
      );
    }
  });

  test('never leaks a session enum name to the screen', () {
    for (final state in RealtimeSessionState.values) {
      expect(
        ConversationCopy.connectingStepLabel(state),
        isNot(contains(state.name)),
      );
    }
  });
}
