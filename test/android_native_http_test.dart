import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/android_native_http.dart';

void main() {
  group('AndroidNativeHttp.decodeResponse', () {
    test('decodes successful GraphQL list response', () {
      final decoded = AndroidNativeHttp.decodeResponse(<String, dynamic>{
        'statusCode': 200,
        'body': '[{"data":{"stream":null}}]',
      });

      expect(decoded, isA<List<dynamic>>());
      expect(decoded.first['data']['stream'], isNull);
    });

    test('accepts numeric status values from platform channels', () {
      final decoded = AndroidNativeHttp.decodeResponse(<String, dynamic>{
        'statusCode': 200.0,
        'body': '{"data":{"ok":true}}',
      });

      expect(decoded['data']['ok'], isTrue);
    });

    test('bounds non-success diagnostics', () {
      final body = 'failure ' * 100;

      expect(
        () => AndroidNativeHttp.decodeResponse(<String, dynamic>{'statusCode': 403, 'body': body}),
        throwsA(
          isA<StateError>().having((error) => error.message.toString().length, 'diagnostic length', lessThan(320)),
        ),
      );
    });

    test('rejects an empty successful response', () {
      expect(
        () => AndroidNativeHttp.decodeResponse(<String, dynamic>{'statusCode': 200, 'body': ''}),
        throwsStateError,
      );
    });
  });
}
