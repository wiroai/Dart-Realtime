import 'dart:async';

import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';

/// Owns the Wiro Run task behind a realtime session: the in-flight request,
/// its cancellation, and the server-side task it produces.
///
/// A task that outlives its caller keeps billing on the server, so the two
/// ways of letting go are deliberately separate: [release] forgets a task that
/// a clean session end already wound down, while [terminateBestEffort] tells
/// the server to tear it down.
final class RealtimeTaskLauncher {
  RealtimeTaskLauncher(this._apiClient);

  final WiroApiClient _apiClient;

  WiroRunResult? _runResult;
  WiroRequestCancellation? _cancellation;

  /// Creates the task, or returns `null` when `isStillWanted` reports that the
  /// caller moved on while the request was in flight.
  ///
  /// A task that arrives too late is terminated here, so callers never have to
  /// remember to clean up after a stale request.
  Future<WiroRunResult?> launch({
    required ModelDefinition model,
    required Map<String, Object?> parameters,
    required bool Function() isStillWanted,
  }) async {
    final cancellation = _apiClient.createCancellation();
    _cancellation = cancellation;
    final runResult = await _apiClient.runModel(
      model: model,
      parameters: parameters,
      cancellation: cancellation,
    );
    if (!isStillWanted()) {
      _terminate(runResult);
      return null;
    }
    _runResult = runResult;
    _cancellation = null;
    return runResult;
  }

  /// Aborts a Run request that has not produced a task yet.
  void cancelPendingRequest() {
    _cancellation?.cancel();
    _cancellation = null;
  }

  /// Forgets the task without terminating it, for a graceful shutdown where
  /// the session end already told the server to wind down.
  void release() {
    _runResult = null;
  }

  /// Terminates the task, for teardowns that cannot rely on a clean session
  /// end. Safe to call when there is nothing to terminate.
  void terminateBestEffort() {
    final runResult = _runResult;
    _runResult = null;
    if (runResult != null) {
      _terminate(runResult);
    }
  }

  void _terminate(WiroRunResult runResult) {
    unawaited(
      _apiClient.terminateTaskBestEffort(
        taskId: runResult.taskId,
        taskToken: runResult.taskToken,
      ),
    );
  }
}
