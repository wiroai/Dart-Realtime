enum RealtimeSessionState {
  idle,
  requestingPermission,
  preparingAudio,
  creatingTask,
  connectingSocket,
  waitingForStream,
  streaming,
  stopping,
  completed,
  failure,
}

extension RealtimeSessionStateX on RealtimeSessionState {
  bool get isIdleLike {
    return this == RealtimeSessionState.idle ||
        this == RealtimeSessionState.completed ||
        this == RealtimeSessionState.failure;
  }

  bool get isActive => !isIdleLike;

  bool get canStart => isIdleLike;

  bool get canStop => isActive;
}
