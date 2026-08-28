import 'dart:async';

import 'package:flutter/foundation.dart';

enum RealtimeSessionOwner {
  conversation,
  transcription,
  speech,
}

@immutable
final class RealtimeSessionLease {
  const RealtimeSessionLease._({
    required this.owner,
    required this.id,
  });

  final RealtimeSessionOwner owner;
  final int id;
}

final class RealtimeSessionGuard extends ValueNotifier<RealtimeSessionLease?> {
  RealtimeSessionGuard() : super(null);

  int _nextId = 0;
  bool _disposed = false;

  RealtimeSessionLease? acquire(RealtimeSessionOwner owner) {
    if (_disposed || value != null) {
      return null;
    }
    final lease = RealtimeSessionLease._(
      owner: owner,
      id: ++_nextId,
    );
    value = lease;
    return lease;
  }

  /// Acquires the lease, waiting out another feature's teardown.
  ///
  /// Leaving a tab ends its session, but the lease is only released once
  /// the microphone and the audio route are actually free — a beat after
  /// the switch. A start that lands inside that beat deserves the session
  /// it asked for, not a busy error, so this waits for the release and
  /// only reports busy once [timeout] says nothing is letting go.
  Future<RealtimeSessionLease?> acquireWhenFree(
    RealtimeSessionOwner owner, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final immediate = acquire(owner);
    if (immediate != null || _disposed) {
      return Future<RealtimeSessionLease?>.value(immediate);
    }
    final completer = Completer<RealtimeSessionLease?>();
    Timer? timer;
    late final VoidCallback onChanged;
    void finish(RealtimeSessionLease? lease) {
      timer?.cancel();
      removeListener(onChanged);
      if (!completer.isCompleted) {
        completer.complete(lease);
      }
    }

    onChanged = () {
      if (_disposed) {
        finish(null);
        return;
      }
      final lease = acquire(owner);
      if (lease != null) {
        finish(lease);
      }
    };
    addListener(onChanged);
    timer = Timer(timeout, () => finish(null));
    return completer.future;
  }

  void release(RealtimeSessionLease? lease) {
    if (!_disposed && lease != null && identical(value, lease)) {
      value = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Waiters must not outlive the guard: wake them so they detach and
    // report busy before the listener list is torn down.
    notifyListeners();
    super.dispose();
  }
}
