import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zinemo/config/api_client.dart';

typedef _Step = Future<ResponseBody> Function(RequestOptions options);

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._steps);

  final List<_Step> _steps;
  int callCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = callCount < _steps.length ? callCount : _steps.length - 1;
    callCount += 1;
    return _steps[index](options);
  }
}

ResponseBody _jsonResponse(int statusCode) {
  return ResponseBody.fromString(
    '{"ok":true}',
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  setUp(() {
    ApiClient.resetForTesting();
  });

  test(
    'retries timeout errors with exponential backoff and succeeds',
    () async {
      final adapter = _ScriptedAdapter([
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
          error: TimeoutException('timeout-1'),
        ),
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
          error: TimeoutException('timeout-2'),
        ),
        (options) async => _jsonResponse(200),
      ]);

      ApiClient.setAdapterForTesting(adapter);

      final response = await ApiClient.get<dynamic>('/health');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 3);
    },
  );

  test('retries 5xx badResponse errors and succeeds', () async {
    final adapter = _ScriptedAdapter([
      (options) async => _jsonResponse(500),
      (options) async => _jsonResponse(500),
      (options) async => _jsonResponse(200),
    ]);

    ApiClient.setAdapterForTesting(adapter);

    final response = await ApiClient.get<dynamic>('/health');

    expect(response.statusCode, 200);
    expect(adapter.callCount, 3);
  });
}
