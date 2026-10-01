// TwitchWebViewHttp over a fake headless browser: only Twitch GraphQL goes
// in, the page's answer comes out, the integrity token is kept and sent
// again, failures are transport failures, and TwitchSite reaches it as the
// last GraphQL fallback.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/platform/twitch_webview_http.dart';

/// Answers each page with the next of [answers] (a value, or an error to
/// throw), recording what it was asked.
final class _FakeBrowser implements HeadlessBrowser {
  new(this.answers);

  final List<Object?> answers;
  final List<({Uri origin, String script, String? proxyRule, Duration timeout})> calls = [];

  @override
  Future<Object?> evaluate({
    required Uri origin,
    required String script,
    required Duration timeout,
    String? proxyRule,
  }) async {
    calls.add((origin: origin, script: script, proxyRule: proxyRule, timeout: timeout));
    final next = answers.removeAt(0);
    if (next is Completer<Object?>) return await next.future;
    if (next is Exception) throw next;
    if (next is Error) throw next;
    return next;
  }
}

final class _Proxy implements ProxyPolicy {
  const new(this.route);

  final ProxyRoute route;

  @override
  ProxyRoute routeFor(String site, Uri url) => route;
}

final class _Refusing implements LiveHttp {
  @override
  Future<LiveResponse> send(LiveRequest request) async =>
      throw TransportFailure(request.site, TransportReason.connect, 'reset after CONNECT');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

const String _query = r'{"query":"{ user(login: \"x\") { id } }"}';

String _envelope({int status = 200, String body = '{"data":{}}', Map<String, Object?>? integrity}) =>
    jsonEncode({'status': status, 'body': body, 'integrity': integrity});

LiveRequest _gql({String deviceId = 'device-1', CancelToken? cancel}) => LiveRequest(
  site: 'twitch',
  url: Uri.parse('https://gql.twitch.tv/gql'),
  method: 'POST',
  headers: {'client-id': TwitchApi.clientId, 'device-id': deviceId, 'cookie': 'auth-token=secret'},
  body: utf8.encode(_query),
  timeout: const Duration(seconds: 7),
  cancel: cancel,
);

void main() {
  final now = DateTime.utc(2026, 10, 1, 6);

  test('only POST https://gql.twitch.tv/gql goes into the page', () async {
    final browser = _FakeBrowser([]);
    final http = TwitchWebViewHttp(proxy: const _Proxy(DirectRoute()), browser: browser);
    for (final request in [
      LiveRequest(site: 'twitch', url: Uri.parse('https://usher.ttvnw.net/api/channel/hls/x.m3u8')),
      LiveRequest(site: 'twitch', url: Uri.parse('https://gql.twitch.tv/gql')),
      LiveRequest(site: 'twitch', url: Uri.parse('http://gql.twitch.tv/gql'), method: 'POST'),
      LiveRequest(site: 'twitch', url: Uri.parse('https://gql.twitch.tv/integrity'), method: 'POST'),
    ]) {
      await expectLater(
        http.send(request),
        throwsA(isA<TransportFailure>().having((e) => e.reason, 'reason', TransportReason.protocol)),
        reason: '${request.method} ${request.url}',
      );
    }
    expect(browser.calls, isEmpty);
  });

  test("the page's status and body; the request, origin, proxy and timeout it got", () async {
    final browser = _FakeBrowser([_envelope(body: '[{"data":{"user":null}}]')]);
    final http = TwitchWebViewHttp(proxy: const _Proxy(HttpProxyRoute('127.0.0.1', 7897)), browser: browser);
    final response = await http.send(_gql());
    expect(response.status, 200);
    expect(response.text, '[{"data":{"user":null}}]');
    final call = browser.calls.single;
    expect(call.origin, TwitchWebViewHttp.origin);
    expect(call.proxyRule, '127.0.0.1:7897');
    expect(call.timeout, const Duration(seconds: 7));
    expect(call.script, contains(jsonEncode(_query)));
    expect(call.script, contains('"Client-ID":"${TwitchApi.clientId}"'));
    expect(call.script, contains('"Device-Id":"device-1"'));
    expect(call.script, contains('const initialToken = "";'));
    expect(call.script, isNot(contains('secret')), reason: 'account cookies stay out of the page');
    expect(call.script, contains(TwitchWebViewHttp.kpsdkScript));
  });

  test('the integrity token is kept per device and sent until shortly before it expires', () async {
    var clock = now;
    final expires = now.add(const Duration(minutes: 10));
    final browser = _FakeBrowser([
      _envelope(integrity: {'token': 'v4.public.abc', 'expiration': expires.millisecondsSinceEpoch}),
      _envelope(),
      _envelope(),
      _envelope(),
    ]);
    final http = TwitchWebViewHttp(proxy: const _Proxy(DirectRoute()), browser: browser, now: () => clock);
    await http.send(_gql());
    expect(http.tokenFor(TwitchApi.clientId, 'device-1')?.token, 'v4.public.abc');
    await http.send(_gql());
    expect(browser.calls[1].script, contains('const initialToken = "v4.public.abc";'));
    await http.send(_gql(deviceId: 'device-2'));
    expect(browser.calls[2].script, contains('const initialToken = "";'), reason: 'bound to its device');
    clock = expires.subtract(const Duration(seconds: 30));
    await http.send(_gql());
    expect(browser.calls[3].script, contains('const initialToken = "";'), reason: 'about to expire');
  });

  test('page failures, timeouts and empty answers are transport failures', () async {
    final browser = _FakeBrowser([
      StateError('Twitch WebView script failed: Twitch KPSDK readiness timed out'),
      TimeoutException('page'),
      null,
      jsonEncode({'status': 'x'}),
    ]);
    final http = TwitchWebViewHttp(proxy: const _Proxy(DirectRoute()), browser: browser);
    final reasons = <TransportReason>[];
    for (var i = 0; i < 4; i++) {
      try {
        await http.send(_gql());
      } on TransportFailure catch (failure) {
        reasons.add(failure.reason);
      }
    }
    expect(reasons, [
      TransportReason.connect,
      TransportReason.timeout,
      TransportReason.protocol,
      TransportReason.protocol,
    ]);
  });

  test('a cancellation ends the request at once', () async {
    final pending = Completer<Object?>();
    final browser = _FakeBrowser([pending]);
    final http = TwitchWebViewHttp(proxy: const _Proxy(DirectRoute()), browser: browser);
    final cancel = CancelToken();
    final sent = http.send(_gql(cancel: cancel));
    cancel.cancel();
    await expectLater(
      sent,
      throwsA(isA<TransportFailure>().having((e) => e.reason, 'reason', TransportReason.cancelled)),
    );
    pending.complete(_envelope());
    final cancelled = CancelToken()..cancel();
    await expectLater(http.send(_gql(cancel: cancelled)), throwsA(isA<TransportFailure>()));
    expect(browser.calls, hasLength(1));
  });

  test('TwitchSite reaches it as the last GraphQL fallback', () async {
    final sample = jsonDecode(File('../../fixtures/twitch/S05-detail-offline/meta.json').readAsStringSync()) as Map;
    final body = File('../../fixtures/twitch/S05-detail-offline/${sample['body']}').readAsStringSync();
    final browser = _FakeBrowser([_envelope(body: body)]);
    final site = TwitchSite(
      _Refusing(),
      gqlFallbacks: [
        _Refusing(),
        TwitchWebViewHttp(proxy: const _Proxy(DirectRoute()), browser: browser),
      ],
    );
    final room = await site.getRoomDetailForRefresh(roomId: 'minecraft');
    expect(room.roomId, 'minecraft');
    expect(room.liveStatus, LiveStatus.offline);
    expect(browser.calls, hasLength(1));
  });

  test('injected on Android only', () {
    expect(TwitchWebViewHttp.isAvailable, Platform.isAndroid);
  });
}
