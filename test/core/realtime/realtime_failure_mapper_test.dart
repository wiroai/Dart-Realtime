import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/realtime/realtime_failure_mapper.dart';

void main() {
  const mapper = RealtimeFailureMapper(fallbackMessage: 'Session failed.');

  test('passes through Wiro failure messages and codes', () {
    const failure = WiroSocketFailure();

    expect(mapper.messageFor(failure), failure.message);
    expect(mapper.codeFor(failure), 'socketConnection');
  });

  test('passes through audio failure messages and codes', () {
    const failure = AudioCaptureFailure();

    expect(mapper.messageFor(failure), failure.message);
    expect(mapper.codeFor(failure), 'captureUnavailable');
  });

  test('collapses unrecognised errors to the fallback', () {
    expect(mapper.messageFor(StateError('boom')), 'Session failed.');
    expect(mapper.codeFor(StateError('boom')), 'unknown');
  });

  test('never leaks raw exception detail into the message', () {
    final leaky = Exception('tasktoken=super-secret-value');

    expect(mapper.messageFor(leaky), 'Session failed.');
    expect(mapper.messageFor(leaky), isNot(contains('secret')));
  });

  test('each feature can supply its own fallback wording', () {
    const transcription = RealtimeFailureMapper(
      fallbackMessage: 'The transcription session could not be completed.',
    );

    expect(
      transcription.messageFor(Object()),
      'The transcription session could not be completed.',
    );
    expect(mapper.messageFor(Object()), 'Session failed.');
  });
}
