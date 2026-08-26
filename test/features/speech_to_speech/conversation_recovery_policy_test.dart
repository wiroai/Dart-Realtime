import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/audio/audio_failure.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/features/speech_to_speech/service/conversation_recovery_policy.dart';

void main() {
  late ConversationRecoveryPolicy policy;

  setUp(() {
    policy = ConversationRecoveryPolicy(
      maxRetryAttempts: 2,
      retryBaseDelay: const Duration(milliseconds: 100),
    );
    addTearDown(policy.dispose);
  });

  test('retries a recoverable failure until the budget is spent', () {
    const error = WiroSocketFailure();

    expect(
      policy.shouldRetry(error, isReconfiguring: false),
      isTrue,
    );
    policy.noteRetryScheduled();
    expect(
      policy.shouldRetry(error, isReconfiguring: false),
      isTrue,
    );
    policy.noteRetryScheduled();
    expect(
      policy.shouldRetry(error, isReconfiguring: false),
      isFalse,
    );
  });

  test('reconfiguring blocks retries', () {
    expect(
      policy.shouldRetry(
        const WiroSocketFailure(),
        isReconfiguring: true,
      ),
      isFalse,
    );
  });

  test('classifies recoverable and unrecoverable failures', () {
    const recoverable = <Object>[
      WiroServerFailure(),
      WiroNetworkFailure(),
      WiroTimeoutFailure(),
      WiroSocketFailure(),
      WiroSocketConnectTimeoutFailure(),
      WiroReadyTimeoutFailure(),
      AudioCaptureFailure(),
      AudioPlaybackFailure(),
    ];
    for (final error in recoverable) {
      expect(policy.isRecoverable(error), isTrue, reason: '$error');
    }

    const unrecoverable = <Object>[
      WiroAuthenticationFailure(),
      WiroApiFailure(),
      WiroCancellationFailure(),
      WiroSessionBusyFailure(),
    ];
    for (final error in unrecoverable) {
      expect(policy.isRecoverable(error), isFalse, reason: '$error');
    }
    expect(policy.isRecoverable(StateError('other')), isFalse);
  });

  test('retry backoff doubles from the base delay', () {
    policy.noteRetryScheduled();
    expect(policy.nextRetryDelay, const Duration(milliseconds: 100));
    expect(policy.retryAttempt, 1);

    policy.noteRetryScheduled();
    expect(policy.nextRetryDelay, const Duration(milliseconds: 200));

    policy.noteRetryScheduled();
    expect(policy.nextRetryDelay, const Duration(milliseconds: 400));
  });

  test('auto-restart budget spends and refills on a healthy send', () {
    fakeAsync((async) {
      var restarts = 0;
      expect(policy.scheduleAutoRestart(() => restarts++), isTrue);
      async.elapse(const Duration(seconds: 5));
      expect(restarts, 1);

      expect(policy.scheduleAutoRestart(() => restarts++), isTrue);
      async.elapse(const Duration(seconds: 10));
      expect(restarts, 2);

      expect(policy.scheduleAutoRestart(() => restarts++), isFalse);

      policy.noteHealthy();
      expect(policy.scheduleAutoRestart(() => restarts++), isTrue);
      async.elapse(const Duration(seconds: 5));
      expect(restarts, 3);
    });
  });

  test('auto-restart delay caps at four times the base', () {
    fakeAsync((async) {
      var fired = 0;
      final wide = ConversationRecoveryPolicy(
        autoRestartDelay: const Duration(seconds: 1),
        maxAutoRestarts: 4,
      );
      addTearDown(wide.dispose);

      wide.scheduleAutoRestart(() => fired++);
      async.elapse(const Duration(milliseconds: 999));
      expect(fired, 0);
      async.elapse(const Duration(milliseconds: 1));
      expect(fired, 1);

      wide.scheduleAutoRestart(() => fired++);
      async.elapse(const Duration(seconds: 2));
      expect(fired, 2);

      wide.scheduleAutoRestart(() => fired++);
      async.elapse(const Duration(seconds: 4));
      expect(fired, 3);

      wide.scheduleAutoRestart(() => fired++);
      async.elapse(const Duration(seconds: 3));
      expect(fired, 3);
      async.elapse(const Duration(seconds: 1));
      expect(fired, 4);
    });
  });
}
