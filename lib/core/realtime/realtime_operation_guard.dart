/// Invalidates in-flight realtime work whose result is no longer wanted.
///
/// Every asynchronous session operation claims an id through [begin]. Awaits
/// inside that operation must re-check [isCurrent] before touching shared
/// state, because a newer operation — or [dispose] — may have superseded it
/// while the await was suspended.
final class RealtimeOperationGuard {
  int _current = 0;
  bool _disposed = false;

  /// The id of the most recently started operation.
  int get current => _current;

  /// Whether the owner has been torn down, making every operation stale.
  ///
  /// Callers use this to refuse work that has no id yet, since [isCurrent]
  /// can only speak for an operation that already started.
  bool get isDisposed => _disposed;

  /// Claims a new operation id and supersedes every earlier one.
  int begin() => ++_current;

  bool isCurrent(int operationId) {
    return !_disposed && operationId == _current;
  }

  void dispose() {
    _disposed = true;
    _current++;
  }
}
