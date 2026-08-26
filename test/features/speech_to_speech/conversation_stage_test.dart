import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/realtime/realtime_session_state.dart';
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

}
