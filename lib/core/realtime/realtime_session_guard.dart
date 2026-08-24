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

  void release(RealtimeSessionLease? lease) {
    if (!_disposed && lease != null && identical(value, lease)) {
      value = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
