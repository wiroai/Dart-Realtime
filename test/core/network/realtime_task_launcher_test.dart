import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
import 'package:wiro_realtime/core/network/realtime_task_launcher.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';

void main() {
  late _FakeWiroApiClient apiClient;
  late RealtimeTaskLauncher launcher;

  setUp(() {
    apiClient = _FakeWiroApiClient();
    launcher = RealtimeTaskLauncher(apiClient);
  });

  Future<WiroRunResult?> launch({bool wanted = true}) {
    return launcher.launch(
      model: WiroModelCatalog.gptRealtimeMini,
      parameters: const {'sampleRate': 24000},
      isStillWanted: () => wanted,
    );
  }

  test('returns the task and forwards the request parameters', () async {
    final runResult = await launch();

    expect(runResult?.taskId, 'task-1');
    expect(apiClient.runCalls, 1);
    expect(apiClient.lastParameters, const {'sampleRate': 24000});
    expect(
      apiClient.lastModel?.modelSlug,
      WiroModelCatalog.gptRealtimeMini.modelSlug,
    );
  });

  test('passes a cancellation the caller can later abort', () async {
    await launch();

    expect(apiClient.lastCancellation, isNotNull);
  });

  test('terminates a task that arrives after the caller moved on', () async {
    final runResult = await launch(wanted: false);

    expect(runResult, isNull);
    expect(apiClient.terminatedTaskIds, ['task-1']);
  });

  test('a stale task is not terminated twice by a later teardown', () async {
    await launch(wanted: false);

    launcher.terminateBestEffort();

    expect(apiClient.terminatedTaskIds, ['task-1']);
  });

  test('terminateBestEffort tears down the live task exactly once', () async {
    await launch();

    launcher
      ..terminateBestEffort()
      ..terminateBestEffort();

    expect(apiClient.terminatedTaskIds, ['task-1']);
  });

  test('release forgets the task without terminating it', () async {
    await launch();

    launcher
      ..release()
      ..terminateBestEffort();

    expect(apiClient.terminatedTaskIds, isEmpty);
  });

  test('cancelPendingRequest aborts an in-flight request', () async {
    apiClient.holdRunModel = true;
    final pending = launch();

    launcher.cancelPendingRequest();

    expect(apiClient.lastCancellation?.isCancelled, isTrue);

    apiClient.completeRunModel();
    await pending;
  });

  test('a completed launch leaves no cancellation to abort', () async {
    await launch();

    launcher.cancelPendingRequest();

    expect(apiClient.lastCancellation?.isCancelled, isFalse);
  });

  test('teardown is safe when nothing was ever launched', () {
    expect(launcher.release, returnsNormally);
    expect(launcher.terminateBestEffort, returnsNormally);
    expect(launcher.cancelPendingRequest, returnsNormally);
    expect(apiClient.terminatedTaskIds, isEmpty);
  });
}

final class _FakeWiroApiClient implements WiroApiClient {
  int runCalls = 0;
  ModelDefinition? lastModel;
  Map<String, Object?>? lastParameters;
  WiroRequestCancellation? lastCancellation;
  List<String> terminatedTaskIds = [];
  bool holdRunModel = false;

  Completer<void>? _gate;

  void completeRunModel() => _gate?.complete();

  @override
  WiroRequestCancellation createCancellation() {
    return lastCancellation = WiroRequestCancellation();
  }

  @override
  Future<WiroRunResult> runModel({
    required ModelDefinition model,
    required Map<String, Object?> parameters,
    WiroRequestCancellation? cancellation,
  }) async {
    runCalls++;
    lastModel = model;
    lastParameters = parameters;
    if (holdRunModel) {
      final gate = _gate = Completer<void>();
      await gate.future;
    }
    return const WiroRunResult(taskId: 'task-1', taskToken: 'token-1');
  }

  @override
  Future<void> terminateTaskBestEffort({
    required String taskId,
    required String taskToken,
  }) async {
    terminatedTaskIds.add(taskId);
  }
}
