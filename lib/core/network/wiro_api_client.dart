import 'package:wiro_realtime/core/auth/wiro_auth_headers.dart';
import 'package:wiro_realtime/core/config/wiro_endpoints.dart';
import 'package:wiro_realtime/core/models/model_definition.dart';
import 'package:wiro_realtime/core/models/wiro_run_result.dart';
import 'package:wiro_realtime/core/network/dto/wiro_run_response_dto.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/network/wiro_http_client.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';

abstract interface class WiroApiClient {
  WiroRequestCancellation createCancellation();

  Future<WiroRunResult> runModel({
    required ModelDefinition model,
    required Map<String, Object?> parameters,
    WiroRequestCancellation? cancellation,
  });

  Future<void> terminateTaskBestEffort({
    required String taskId,
    required String taskToken,
  });
}

final class DefaultWiroApiClient implements WiroApiClient {
  DefaultWiroApiClient(this._httpClient, this._authHeaders);

  final WiroHttpClient _httpClient;
  final WiroAuthHeaders _authHeaders;

  @override
  WiroRequestCancellation createCancellation() {
    return WiroRequestCancellation();
  }

  @override
  Future<WiroRunResult> runModel({
    required ModelDefinition model,
    required Map<String, Object?> parameters,
    WiroRequestCancellation? cancellation,
  }) async {
    final response = await _httpClient.post(
      path: WiroEndpoints.runPath(
        owner: model.owner,
        model: model.slug,
      ),
      headers: _authHeaders.create(),
      body: parameters,
      cancellation: cancellation,
    );

    _validateStatusCode(response.statusCode);
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const WiroMalformedResponseFailure();
    }

    final WiroRunResponseDto dto;
    try {
      dto = WiroRunResponseDto.fromJson(data);
    } on Object {
      throw const WiroMalformedResponseFailure();
    }

    final result = dto.result;
    final errors = dto.errors;
    if (result == null || errors == null) {
      throw const WiroMalformedResponseFailure();
    }
    if (!result) {
      throw const WiroApiFailure();
    }
    final taskId = dto.taskId;
    final taskToken = dto.taskToken;
    if (errors.isNotEmpty ||
        taskId == null ||
        taskId.trim().isEmpty ||
        taskToken == null ||
        taskToken.trim().isEmpty) {
      throw const WiroMalformedResponseFailure();
    }

    return WiroRunResult(
      taskId: taskId,
      taskToken: taskToken,
    );
  }

  @override
  Future<void> terminateTaskBestEffort({
    required String taskId,
    required String taskToken,
  }) async {
    try {
      final response = await _httpClient.post(
        path: WiroEndpoints.taskCancelPath,
        headers: _authHeaders.create(),
        body: {'taskid': taskId},
      );
      if (_isSuccessfulTaskAction(response)) {
        return;
      }
    } on Object {
      // The task may already be running; try the verified Kill endpoint.
    }

    try {
      await _httpClient.post(
        path: WiroEndpoints.taskKillPath,
        headers: _authHeaders.create(),
        body: {'socketaccesstoken': taskToken},
      );
    } on Object {
      // Abnormal-shutdown task termination is deliberately best effort.
    }
  }

  bool _isSuccessfulTaskAction(WiroHttpResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }
    final data = response.data;
    return data is Map<String, dynamic> && data['result'] == true;
  }

  void _validateStatusCode(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    switch (statusCode) {
      case 401:
      case 403:
        throw const WiroAuthenticationFailure();
      case 429:
        throw const WiroRateLimitFailure();
      default:
        throw const WiroServerFailure();
    }
  }
}
