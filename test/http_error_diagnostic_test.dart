import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/custom_interceptor.dart';

void main() {
  test('HTTP diagnostics never print signed URLs, payloads, credentials or nested errors', () {
    final messages = <String>[];
    final interceptor = CustomLogInterceptor(errorLogger: (message, _) => messages.add(message));
    final request = RequestOptions(
      path: 'https://fixture-user:fixture-password@cdn.example/fixture-path-secret/stream.flv?token=fixture-token#fixture-fragment',
      method: 'POST',
      extra: {'ts': DateTime.now().millisecondsSinceEpoch - 25},
      queryParameters: {'acfun.api.visitor_st': 'fixture-visitor', 'authorId': 'fixture-author'},
      data: {
        'password': 'fixture-body-secret',
        'nested': {'cookie': 'fixture-nested-secret'},
      },
      headers: {'Cookie': 'fixture-cookie', 'Access-Token': 'fixture-access-token'},
    );
    final error = DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      message: 'request failed with fixture-exception-secret',
      error: StateError('fixture-inner-secret'),
      response: Response(
        requestOptions: request,
        statusCode: 403,
        headers: Headers.fromMap({
          'set-cookie': ['fixture-response-cookie'],
        }),
        data: {'access_token': 'fixture-response-token', 'url': 'fixture-response-url'},
      ),
    );
    final handler = _RecordingErrorHandler();
    interceptor.onError(error, handler);
    expect(handler.forwarded, same(error));
    expect(messages, hasLength(1));
    expect(messages.single, contains('cdn.example'));
    expect(messages.single, contains('403'));
    expect(messages.single, contains('POST'));
    expect(messages.single, isNot(contains('fixture-')));
  });

  for (final timestamp in <Object?>[null, 'invalid', -1]) {
    test('HTTP error survives missing or invalid request timestamp $timestamp', () {
      final messages = <String>[];
      final interceptor = CustomLogInterceptor(errorLogger: (message, _) => messages.add(message));
      final request = RequestOptions(path: 'https://api.example/live', extra: {'ts': timestamp});
      final handler = _RecordingErrorHandler();
      expect(() => interceptor.onError(DioException(requestOptions: request), handler), returnsNormally);
      expect(handler.forwarded, isNotNull);
      expect(messages, hasLength(1));
    });
  }

  test('a failed diagnostic sink never replaces the original HTTP failure', () {
    final interceptor = CustomLogInterceptor(errorLogger: (_, _) => throw StateError('sink unavailable'));
    final handler = _RecordingErrorHandler();
    final request = RequestOptions(
      path: 'https://api.example/live',
      extra: {'ts': DateTime.now().millisecondsSinceEpoch},
    );
    expect(() => interceptor.onError(DioException(requestOptions: request), handler), returnsNormally);
    expect(handler.forwarded, isNotNull);
  });

  test('large server bodies stay structural and future timestamps remain unknown', () {
    final request = RequestOptions(
      path: 'https://api.example/live',
      extra: {'ts': DateTime.now().millisecondsSinceEpoch + 60000},
      data: 'private-body' * 100000,
    );
    final result = formatHttpFailureDiagnostic(
      DioException(
        requestOptions: request,
        response: Response(requestOptions: request, data: List.filled(10000, 'private-response')),
      ),
    );
    expect(result, contains('Time:unknown'));
    expect(result, contains('text(1200000)'));
    expect(result, contains('list(10000)'));
    expect(result, isNot(contains('private-')));
    expect(result.length, lessThan(1024));
  });
}

// Observe the next-interceptor contract without creating Dio's private error
// Future outside its pipeline (which would itself be an unobserved error).
class _RecordingErrorHandler extends ErrorInterceptorHandler {
  DioException? forwarded;
  @override
  void next(DioException error) => forwarded = error;
}
