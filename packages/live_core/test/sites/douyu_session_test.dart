// Douyu login cookie (spec/sites/douyu.md §8): session token, expiry, state,
// renewal credentials, Set-Cookie merging and the passport renewal request.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

String _jwt(Map<String, Object?> payload) =>
    'eyJhbGciOiJIUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.sig';

void main() {
  final now = DateTime.utc(2026, 9, 28, 12);
  final inTwoDays = now.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000;
  final anHourAgo = now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;

  group('§8.1 token and expiry', () {
    test('the token is acf_jwt_token, else acf_auth, else dy_auth', () {
      expect(DouyuSession.sessionToken('dy_auth=w; acf_auth=a; acf_jwt_token=j'), 'j');
      expect(DouyuSession.sessionToken('dy_auth=w; acf_auth=a'), 'a');
      expect(DouyuSession.sessionToken('Cookie: dy_did=1; dy_auth=w'), 'w');
      expect(DouyuSession.sessionToken('dy_did=1; acf_did=1'), isNull);
      expect(DouyuSession.sessionToken('dy_auth='), isNull, reason: 'blank is absent');
    });

    test('a JWT gives its own exp; dy_auth lasts seven days from the save; unknown is null', () {
      final jwt = 'acf_jwt_token=${_jwt({'exp': inTwoDays})}';
      expect(DouyuSession.expiry(jwt), DateTime.fromMillisecondsSinceEpoch(inTwoDays * 1000));
      expect(DouyuSession.expiry('dy_auth=w', savedAt: now), now.add(const Duration(days: 7)));
      expect(DouyuSession.expiry('dy_auth=w'), isNull, reason: 'no save time: not guessed');
      expect(DouyuSession.expiry('acf_auth=not.a.jwt'), isNull);
      expect(DouyuSession.expiry('dy_did=1'), isNull);
    });

    test('five states', () {
      final expired = 'dy_did=d; acf_jwt_token=${_jwt({'exp': anHourAgo})}';
      expect(DouyuSession.state('', now: now), DouyuSessionState.none);
      expect(DouyuSession.state('dy_did=d', now: now), DouyuSessionState.guest);
      expect(DouyuSession.state('dy_auth=w', now: now), DouyuSessionState.valid, reason: 'unknown end is valid');
      expect(DouyuSession.state('acf_jwt_token=${_jwt({'exp': inTwoDays})}', now: now), DouyuSessionState.valid);
      expect(DouyuSession.state(expired, now: now), DouyuSessionState.expired);
      expect(DouyuSession.state(expired, now: now, ltp0: 'l', did: 'd'), DouyuSessionState.expiredRefreshable);
      expect(
        DouyuSession.state('dy_auth=w', now: now, savedAt: now.subtract(const Duration(days: 8))),
        DouyuSessionState.expired,
      );
    });

    test('§8.2 renew with no token or inside the last day; an unknown end is left alone', () {
      expect(DouyuSession.shouldRenew('dy_did=d', now: now), isTrue);
      expect(DouyuSession.shouldRenew('dy_auth=w', now: now), isFalse);
      expect(DouyuSession.shouldRenew('dy_auth=w', now: now, savedAt: now.subtract(const Duration(days: 6))), isTrue);
      expect(DouyuSession.shouldRenew('dy_auth=w', now: now, savedAt: now.subtract(const Duration(days: 5))), isFalse);
    });
  });

  group('§8.2 credentials', () {
    test('typed > cookie > stored; the device id never comes from elsewhere', () {
      expect(DouyuSession.credentials('LTP0=c; dy_did=cd', typedLtp0: ' t ', storedLtp0: 's', storedDid: 'sd'), (
        ltp0: 't',
        did: 'cd',
      ));
      expect(DouyuSession.credentials('dy_auth=w', storedLtp0: 's', storedDid: 'sd'), (ltp0: 's', did: 'sd'));
      expect(DouyuSession.credentials('dy_auth=w', storedLtp0: 's'), (ltp0: 's', did: null));
    });

    test('§8.4 a passport cookie has renewal fields and no session', () {
      expect(DouyuSession.isPassportCookie('LTP0=l; dy_did=d; acf_ssid=x'), isTrue);
      expect(DouyuSession.isPassportCookie('acf_stk=s'), isTrue);
      expect(DouyuSession.isPassportCookie('LTP0=l; dy_auth=w'), isFalse);
      expect(DouyuSession.isPassportCookie('dy_did=d'), isFalse);
    });
  });

  test('§8.2 merge keeps unmentioned fields, drops emptied ones, ignores attributes', () {
    final merged = DouyuSession.merge('Cookie: dy_did=d; LTP0=l; acf_auth=old; acf_stk=s', [
      'acf_auth=new; Path=/; Domain=.douyu.com; HttpOnly',
      'acf_stk=; Max-Age=0',
      'Secure=x',
      'acf_uid=7; Expires=Wed, 01 Oct 2026 00:00:00 GMT',
    ]);
    expect(merged, 'dy_did=d; LTP0=l; acf_auth=new; acf_uid=7');
  });

  group('§8.2 renewSession', () {
    ReplaySample passport({List<String> setCookie = const []}) => ReplaySample(
      method: 'GET',
      url: Uri.parse(
        'https://passport.douyu.com/lapi/passport/iframe/safeAuth?client_id=1&callback=axiosJsonpCallback',
      ),
      status: 200,
      headers: {if (setCookie.isNotEmpty) 'set-cookie': setCookie},
      bytes: utf8.encode('axiosJsonpCallback({"error":0})'),
    );

    test('sends only dy_did and LTP0 and returns the merged cookie', () async {
      final http = ReplayHttp(
        [
          passport(
            setCookie: [
              'acf_jwt_token=${_jwt({'exp': inTwoDays})}; Path=/',
            ],
          ),
        ],
        ignoredQuery: {'t', '_'},
      );
      final site = DouyuSite(http, now: () => now);
      final renewed = await site.renewSession(cookie: 'dy_did=d; acf_jwt_token=old; LTP0=l', ltp0: 'l', did: 'd');
      expect(DouyuSession.expiry(renewed!), DateTime.fromMillisecondsSinceEpoch(inTwoDays * 1000));
      expect(renewed, contains('LTP0=l'), reason: 'unmentioned fields stay');
      expect(http.requests.single.headers['cookie'], 'dy_did=d;LTP0=l');
      expect(http.requests.single.url.queryParameters['t'], '${now.millisecondsSinceEpoch}');
    });

    test('no Set-Cookie, or none with a session token, renews nothing', () async {
      final site = DouyuSite(
        ReplayHttp(
          [
            passport(),
            passport(setCookie: ['acf_jwt_token=; Max-Age=0']),
          ],
          ignoredQuery: {'t', '_'},
        ),
        now: () => now,
      );
      expect(await site.renewSession(cookie: 'dy_did=d; acf_jwt_token=a', ltp0: 'l', did: 'd'), isNull);
      expect(await site.renewSession(cookie: 'dy_did=d; acf_jwt_token=a', ltp0: 'l', did: 'd'), isNull);
    });

    test('a transport failure is a NetworkFailure', () async {
      final site = DouyuSite(_FailingHttp(), now: () => now);
      await expectLater(site.renewSession(cookie: 'acf_auth=a', ltp0: 'l', did: 'd'), throwsA(isA<NetworkFailure>()));
    });
  });
}

final class _FailingHttp implements LiveHttp {
  @override
  Future<LiveResponse> send(LiveRequest request) async =>
      throw const TransportFailure('douyu', TransportReason.connect, 'offline');

  @override
  void close() {}
}
