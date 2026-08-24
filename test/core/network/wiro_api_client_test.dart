import 'package:flutter_test/flutter_test.dart';
import 'package:wiro_realtime/core/auth/wiro_auth_headers.dart';
import 'package:wiro_realtime/core/auth/wiro_credentials.dart';
import 'package:wiro_realtime/core/models/wiro_model_catalog.dart';
import 'package:wiro_realtime/core/network/wiro_api_client.dart';
import 'package:wiro_realtime/core/network/wiro_failure.dart';
import 'package:wiro_realtime/core/network/wiro_http_client.dart';
import 'package:wiro_realtime/core/network/wiro_request_cancellation.dart';

void main() {
  test('returns typed task identifiers from a Run response', () async {
    final httpClient = FakeWiroHttpClient(
      response: const WiroHttpResponse(
        statusCode: 200,
        data: {
          'result': true,
          'errors': <Object?>[],
          'taskid': '2221',
          'socketaccesstoken': 'task-token',
        },
      ),
    );
    final client = createClient(httpClient);
    final cancellation = WiroRequestCancellation();

    final result = await client.runModel(
      model: WiroModelCatalog.gptRealtimeMini,
      parameters: const {'voice': 'alloy'},
      cancellation: cancellation,
    );

    expect(result.taskId, '2221');
    expect(result.taskToken, 'task-token');
    expect(httpClient.path, '/Run/openai/gpt-realtime-mini');
    expect(httpClient.body, {'voice': 'alloy'});
    expect(httpClient.cancellation, same(cancellation));
    expect(httpClient.headers, {'x-api-key': 'api-key'});
  });

  test('rejects malformed successful responses', () async {
    final client = createClient(
      FakeWiroHttpClient(
        response: const WiroHttpResponse(
          statusCode: 200,
          data: {
            'result': true,
            'errors': <Object?>[],
            'taskid': '2221',
          },
        ),
      ),
    );

    await expectLater(
      client.runModel(
        model: WiroModelCatalog.gptRealtimeMini,
        parameters: const {},
      ),
      throwsA(isA<WiroMalformedResponseFailure>()),
    );
  });

  test('redacts credentials and server errors from failures', () async {
    const apiKey = 'private-api-key';
    const apiSecret = 'private-api-secret';
    final client = DefaultWiroApiClient(
      FakeWiroHttpClient(
        response: const WiroHttpResponse(
          statusCode: 200,
          data: {
            'result': false,
            'errors': [
              {
                'message': 'Rejected private-api-key and private-api-secret',
              },
            ],
            'taskid': null,
            'socketaccesstoken': null,
          },
        ),
      ),
      WiroAuthHeaders(
        credentials: const WiroCredentials(
          apiKey: apiKey,
          apiSecret: apiSecret,
        ),
      ),
    );

    try {
      await client.runModel(
        model: WiroModelCatalog.gptRealtimeMini,
        parameters: const {},
      );
      fail('Expected WiroApiFailure.');
    } on WiroApiFailure catch (failure) {
      expect(failure.toString(), isNot(contains(apiKey)));
      expect(failure.toString(), isNot(contains(apiSecret)));
      expect(failure.toString(), isNot(contains('Rejected')));
    }
  });

  test('maps unauthorized responses to an authentication failure', () async {
    final client = createClient(
      FakeWiroHttpClient(
        response: const WiroHttpResponse(
          statusCode: 401,
          data: {
            'result': false,
            'errors': <Object?>[],
          },
        ),
      ),
    );

    await expectLater(
      client.runModel(
        model: WiroModelCatalog.gptRealtimeMini,
        parameters: const {},
      ),
      throwsA(isA<WiroAuthenticationFailure>()),
    );
  });

  test('falls back from task cancel to task kill', () async {
    final httpClient = FakeWiroHttpClient(
      response: const WiroHttpResponse(
        statusCode: 409,
        data: {'result': false},
      ),
    );
    final client = createClient(httpClient);

    await client.terminateTaskBestEffort(
      taskId: 'task-id',
      taskToken: 'task-token',
    );

    expect(httpClient.paths, [
      '/Task/Cancel',
      '/Task/Kill',
    ]);
    expect(httpClient.body, {
      'socketaccesstoken': 'task-token',
    });
  });

  test('failure exposes a stable machine-readable code', () {
    const failure = WiroSessionBusyFailure();

    expect(failure.code, WiroFailureCode.sessionBusy);
    expect(failure.diagnostics, isEmpty);
  });
}

DefaultWiroApiClient createClient(WiroHttpClient httpClient) {
  return DefaultWiroApiClient(
    httpClient,
    WiroAuthHeaders(
      credentials: const WiroCredentials(apiKey: 'api-key'),
    ),
  );
}

final class FakeWiroHttpClient implements WiroHttpClient {
  FakeWiroHttpClient({required this.response});

  final WiroHttpResponse response;

  String? path;
  Map<String, String>? headers;
  Map<String, Object?>? body;
  WiroRequestCancellation? cancellation;
  final List<String> paths = [];

  @override
  void close() {}

  @override
  Future<WiroHttpResponse> post({
    required String path,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    WiroRequestCancellation? cancellation,
  }) async {
    paths.add(path);
    this.path = path;
    this.headers = headers;
    this.body = body;
    this.cancellation = cancellation;
    return response;
  }
}
