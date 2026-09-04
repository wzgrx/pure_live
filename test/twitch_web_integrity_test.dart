import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/utils/twitch/twitch_web_integrity.dart';

void main() {
  test('browser integrity bootstrap binds the client and device identity', () {
    final script = TwitchWebIntegrityProvider.buildBootstrapScript(
      clientId: 'client-id-fixture',
      deviceId: '0123456789abcdef0123456789abcdef',
    );

    expect(script, contains(TwitchWebIntegrityProvider.scriptUrl));
    expect(script, contains('client-id-fixture'));
    expect(script, contains('0123456789abcdef0123456789abcdef'));
    expect(script, contains('X-Device-Id'));
    expect(script, contains("document.addEventListener('kpsdk-load'"));
    expect(script, contains("document.addEventListener('kpsdk-ready'"));
    expect(script, contains("credentials: 'omit'"));
  });

  test('browser GraphQL fallback keeps the request body and identity together', () {
    const body = '{"operationName":"DirectoryPage_Game"}';
    final script = TwitchWebIntegrityProvider.buildGraphQlScript(
      body: body,
      clientId: 'client-id-fixture',
      deviceId: '0123456789abcdef0123456789abcdef',
    );

    expect(script, contains('https://gql.twitch.tv/gql'));
    expect(script, contains('client-id-fixture'));
    expect(script, contains('0123456789abcdef0123456789abcdef'));
    expect(script, contains('Device-Id'));
    expect(script, isNot(contains('X-Device-Id')));
    expect(script, contains('DirectoryPage_Game'));
    expect(script, contains("credentials: 'omit'"));
    expect(script, isNot(contains('Cookie')));
    expect(script, isNot(contains('Authorization')));
  });
}
