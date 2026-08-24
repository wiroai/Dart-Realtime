import 'dart:async';

final class WiroRequestCancellation {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!isCancelled) {
      _completer.complete();
    }
  }
}
