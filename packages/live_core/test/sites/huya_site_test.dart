// HuyaSite end to end over the recorded Huya responses (ReplayHttp), plus
// the AntiCode signing, Tars/WUP codec and link rules. The signing and codec
// vectors were computed by running the legacy implementation
// (HuyaSite.buildAntiCode, BaseTarsHttp.buildRequest / tupResponseDecode).
//
// The recorded samples scrub `fm` into bytes without the `$0`–`$3`
// placeholders and there are no WUP samples, so the stream tests patch a
// synthetic template into the AntiCodes and answer WUP from a script.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:live_core/src/sites/huya/huya_sign.dart';
import 'package:live_core/src/sites/huya/huya_tars.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/huya';

/// `_` is the request time; the search `uid` was scrubbed in the samples.
const _ignored = {'_', 'uid'};

/// The S05 capture instant, 1790502272850 ms.
final _now = DateTime.utc(2026, 9, 27, 9, 44, 32, 850);

/// S05-multicdn `lPresenterUid` and stream names.
const _presenter = 1346609715;
const _stream1 = '78941969-2559461593-10992803837303062528-2693342886-10057-A-0-1-imgplus';
const _stream2 = '78941969-2601386338-11172869245971202048-3120471182-10057-A-0-1-imgplus';

/// A shorter stream name used by some codec and signing vectors.
const _vectorStream = '78941969-2559461593-10992803837303062528';

/// Legacy `buildRequest` of the native getCdnTokenInfoEx for [_stream1].
const _nativeRequestStream1 =
    '000000b210032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d000100840800010604745265711d'
    '0000770a0600164737383934313936392d323535393436313539332d31303939323830333833373330333036323532382d3236'
    '39333334323838362d31303035372d412d302d312d696d67706c75732c3a0c16002600361770635f6578652637303630303030'
    '266f6666696369616c46005c660076000b40420b8c980ca80c';

/// An anonymous-login viewer UID above 2^32.
const _viewer = 1400123456789;

const _webTemplate = r'DWq8BcJ3h6DJt6TY_$0_$1_$2_$3';
const _nativeTemplate = r'native|$0|$1|$2|$3';
const _mobileUserAgent =
    'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0';

String _fm(String template) => Uri.encodeComponent(base64Encode(utf8.encode(template)));

String _wsTime(DateTime time) => (time.millisecondsSinceEpoch ~/ 1000).toRadixString(16);

Uint8List _hex(String hex) =>
    Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

ReplaySample _sample(String name) => ReplaySample.load('$_root/$name');

/// [name] with every AntiCode rewritten by [antiCode] and, when given, only
/// the [flv] / [hls] CDNs left in `multiLine`.
ReplaySample _patched(String name, {String Function(String antiCode)? antiCode, Set<String>? flv, Set<String>? hls}) {
  final sample = _sample(name);
  final body = jsonDecode(utf8.decode(sample.bytes)) as Map<String, dynamic>;
  final stream = (body['data'] as Map<String, dynamic>)['stream'] as Map<String, dynamic>;
  if (antiCode != null) {
    for (final base in (stream['baseSteamInfoList'] as List).cast<Map<String, dynamic>>()) {
      for (final key in ['sFlvAntiCode', 'sHlsAntiCode']) {
        base[key] = antiCode(base[key] as String);
      }
    }
  }
  for (final (key, keep) in [('flv', flv), ('hls', hls)]) {
    if (keep == null) continue;
    final group = stream[key] as Map<String, dynamic>;
    group['multiLine'] = [
      for (final line in (group['multiLine'] as List).cast<Map<String, dynamic>>())
        if (keep.contains(line['cdnType'])) line,
    ];
  }
  return ReplaySample(
    method: sample.method,
    url: sample.url,
    status: sample.status,
    headers: sample.headers,
    bytes: utf8.encode(jsonEncode(body)),
  );
}

/// Replaces the scrubbed `fm` with the synthetic web template.
String _withTemplate(String antiCode) => antiCode.replaceFirst(RegExp('fm=[^&]*'), 'fm=${_fm(_webTemplate)}');

LiveResponse _wupAnswer(LiveRequest request, {int code = 0, String token = '', int expireTime = 0}) => LiveResponse(
  status: 200,
  url: request.url,
  bytes: WupPacket(
    servant: 'liveui',
    function: 'getCdnTokenInfoEx',
    params: {
      '': WupPacket.intParam(code),
      'tRsp': WupPacket.structParam(
        (writer) => writer
          ..writeString(0, token)
          ..writeInt(1, expireTime),
      ),
    },
  ).encode(),
);

LiveResponse _loginAnswer(LiveRequest request, int uid) => LiveResponse(
  status: 200,
  url: request.url,
  bytes: utf8.encode(
    jsonEncode({
      'returnCode': 0,
      'data': {'uid': uid},
    }),
  ),
);

/// ReplayHttp for the recorded GETs, scripted answers for WUP and
/// anonymous login, and an optional queue of `profileRoom` answers.
final class _Http implements LiveHttp {
  new(List<ReplaySample> samples, {this.wup, this.login, List<ReplaySample> profiles = const []})
    : _replay = ReplayHttp(samples, ignoredQuery: _ignored),
      _profiles = [...profiles];

  final ReplayHttp _replay;
  final List<ReplaySample> _profiles;

  /// Answers `getCdnTokenInfoEx` given its decoded `tReq`.
  final LiveResponse Function(LiveRequest request, TarsStruct tReq)? wup;

  /// Answers `anonymousLogin`.
  final LiveResponse Function(LiveRequest request)? login;

  final List<LiveRequest> requests = [];

  List<LiveRequest> on(String host) => [
    for (final request in requests)
      if (request.url.host == host) request,
  ];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    switch (request.url.host) {
      case 'wup.huya.com':
        final packet = WupPacket.decode(request.body!);
        expect((packet.servant, packet.function), ('liveui', 'getCdnTokenInfoEx'));
        return wup!(request, TarsStruct.decode(packet.params['tReq']!).struct(0)!);
      case 'udblgn.huya.com':
        return login!(request);
      case 'mp.huya.com' when _profiles.isNotEmpty:
        final sample = _profiles.removeAt(0);
        return LiveResponse(status: sample.status, headers: sample.headers, bytes: sample.bytes, url: request.url);
    }
    return await _replay.send(request);
  }

  @override
  void close() {}
}

HuyaSite _site(_Http http, {CookieVault? cookies, HuyaSignClock? clock}) =>
    HuyaSite(http, cookies: cookies, now: () => _now, random: Random(1), signClock: clock ?? HuyaSignClock());

RoomDetail _room(String roomId) => RoomDetail(
  card: RoomCard(ref: RoomRef('huya', roomId), title: '', anchorName: '', state: LiveState.live),
  link: Uri.parse('https://www.huya.com/$roomId'),
);

/// The signing millisecond of a non-WAP signed URL: `seqid − unrotate(u)`.
int _millis(Uri url) =>
    int.parse(url.queryParameters['seqid']!) - HuyaParse.unrotateUid(int.parse(url.queryParameters['u']!));

/// Recomputes [url]'s wsSecret from [template] without HuyaSign (§6.4).
void _expectSigned(Uri url, String template, {required int uid}) {
  final query = url.queryParameters;
  expect(query.containsKey('fm'), isFalse, reason: 'fm never reaches the CDN');
  expect(query['u'], '${HuyaParse.rotateUid(uid)}');
  expect(query['ver'], '1');
  final hash = md5.convert(utf8.encode('${query['seqid']}|${query['ctype']}|${query['t']}')).toString();
  final stream = url.pathSegments.last.replaceFirst(RegExp(r'\.(flv|m3u8)$'), '');
  final input = template
      .replaceFirst(r'$0', query['u']!)
      .replaceFirst(r'$1', stream)
      .replaceFirst(r'$2', hash)
      .replaceFirst(r'$3', query['wsTime']!);
  expect(query['wsSecret'], md5.convert(utf8.encode(input)).toString());
}

void main() {
  group('§6.4 signing (legacy buildAntiCode vectors)', () {
    const legacy = [
      (
        antiCode: 'wsSecret=stale&wsTime=6b49d278&fm=cHJlZml4XyQwXyQxXyQyXyQz&ctype=huya_live&fs=bgct&t=100&codec=264',
        stream: 'stream-name',
        uid: 1400123456789,
        now: 1800000000000,
        signed:
            'wsTime=6b49d278&ctype=huya_live&fs=bgct&t=100&codec=264&wsSecret=461723da82a735de0c2299b561428ec2'
            '&seqid=3200123456789&ver=1&u=1399563556349',
      ),
      (
        antiCode:
            'wsTime=6b49d278&fm=cHJlZml4LXYyfCQxfHZpZXdlcj0kMHxoYXNoPSQyfGxlYXNlPSQzfHRhaWw%3D&ctype=huya_live'
            '&t=100&codec=264',
        stream: 'stream-name',
        uid: 1400123456789,
        now: 1800000000000,
        signed:
            'wsTime=6b49d278&ctype=huya_live&t=100&codec=264&wsSecret=74fa5368c8966e5e6d007a6acfd3f941'
            '&seqid=3200123456789&ver=1&fs=bgct&u=1399563556349',
      ),
      (
        antiCode: 'wsTime=6b49d278&fm=cHJlZml4XyQwXyQxXyQyXyQz&t=100',
        stream: 'stream-name',
        uid: 1471259343403,
        now: 1800000000000,
        signed:
            'wsTime=6b49d278&t=100&wsSecret=4ebc14c64af251c9798fda4926b9da4d&seqid=3271259343403'
            '&ctype=huya_webh5&ver=1&fs=bgct&u=1472703638413',
      ),
      (
        antiCode:
            'wsSecret=30f2c946b62c16182f518a97aeae1fe4&wsTime=6aba3701'
            '&fm=RFdxOEJjSjNoNkRKdDZUWV8kMF8kMV8kMl8kMw%3D%3D&ctype=tars_mp&fs=bgct&t=102',
        stream: _vectorStream,
        uid: _presenter,
        now: 1790502272850,
        signed:
            'wsTime=6aba3701&ctype=tars_mp&fs=bgct&t=102&wsSecret=aef6026e05937ac844020a139aca4dc9'
            '&seqid=1791848882565&ver=1&u=1134703440',
      ),
      (
        antiCode: 'wsTime=6aba3701&fm=bmF0aXZlXyQwXyQxXyQyXyQz&ctype=huya_pc_exe&t=100',
        stream: _vectorStream,
        uid: _presenter,
        now: 1790502272850,
        signed:
            'wsTime=6aba3701&ctype=huya_pc_exe&t=100&wsSecret=2d7f25a2f40f9051a4c6fada21554094'
            '&seqid=1791848882565&ver=1&fs=bgct&u=1134703440',
      ),
    ];
    for (final (index, vector) in legacy.indexed) {
      test('vector ${index + 1}', () {
        final signed = HuyaSign.sign(
          vector.antiCode,
          streamName: vector.stream,
          uid: vector.uid,
          clock: HuyaSignClock(),
          now: DateTime.fromMillisecondsSinceEpoch(vector.now, isUtc: true),
        );
        expect(signed, vector.signed);
      });
    }

    test('WAP (t=103) signs with the plain UID and adds uid and a random uuid', () {
      final signed = HuyaSign.sign(
        'wsTime=6b49d278&fm=d2FwXyQwXyQxXyQyXyQz&ctype=huya_live&t=103&sphd=264_*',
        streamName: 'stream-name',
        uid: 1400123456789,
        clock: HuyaSignClock(),
        now: DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true),
        random: Random(3),
      );
      // Legacy re-encodes untouched parameters (sphd=264_%2A); v4 keeps their
      // original spelling. The signature does not cover them.
      expect(
        signed.replaceFirst(RegExp(r'uuid=\d+$'), 'uuid=*'),
        'wsTime=6b49d278&ctype=huya_live&t=103&sphd=264_*&wsSecret=e8c5486afea4e995cd0f6893295be906'
        '&seqid=3200123456789&ver=1&fs=bgct&uid=1400123456789&uuid=*',
      );
      expect(Uri.splitQueryString(signed).containsKey('u'), isFalse);
    });

    test('rotl64 matches legacy rotateViewerUid32', () {
      expect(HuyaParse.rotateUid(_presenter), 1134703440);
      expect(HuyaParse.rotateUid(1400123456789), 1399563556349);
      expect(HuyaParse.rotateUid(1471259343403), 1472703638413);
    });

    final now = DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true);
    String code(String template, {Duration wsTimeFromNow = const Duration(minutes: 2)}) =>
        'wsTime=${_wsTime(now.add(wsTimeFromNow))}&fm=${_fm(template)}&ctype=huya_live&t=100';
    String sign(String antiCode, {DateTime? at, HuyaSignClock? clock}) =>
        HuyaSign.sign(antiCode, streamName: 's', uid: 123, clock: clock ?? HuyaSignClock(), now: at ?? now);
    Matcher fails(HuyaSignFailureKind kind) =>
        throwsA(isA<HuyaSignFailure>().having((failure) => failure.kind, 'kind', kind));

    test('malformed templates fail before any URL is built (REG-HUYA-005)', () {
      expect(() => sign(code(r'prefix_$0_$1')), fails(HuyaSignFailureKind.malformed));
      expect(() => sign('fm=${_fm(r'$0$1$2$3')}&ctype=x'), fails(HuyaSignFailureKind.malformed));
      expect(() => sign('wsTime=zz&fm=${_fm(r'$0$1$2$3')}'), fails(HuyaSignFailureKind.malformed));
      expect(() => sign('wsTime=6b49d278&fm=%%%'), fails(HuyaSignFailureKind.malformed));
      expect(() => sign('wsTime=6b49d278&fm=@@@@'), fails(HuyaSignFailureKind.malformed));
      // The scrubbed samples carry exactly such an fm (no placeholders).
      final data = (jsonDecode(Fixture.load('huya', 'S05-multicdn').body) as Map)['data'] as Map;
      final base = ((data['stream'] as Map)['baseSteamInfoList'] as List).first as Map;
      expect(() => sign(base['sFlvAntiCode'] as String), fails(HuyaSignFailureKind.malformed));
    });

    test('wsTime is never extended: kept as served, expired past wsTime + 300 s (REG-HUYA-004)', () {
      final nearEnd = code(r'$0$1$2$3', wsTimeFromNow: const Duration(seconds: -299));
      final signed = Uri.splitQueryString(sign(nearEnd));
      expect(signed['wsTime'], _wsTime(now.subtract(const Duration(seconds: 299))));
      final boundary = code(r'$0$1$2$3', wsTimeFromNow: const Duration(seconds: -300));
      expect(Uri.splitQueryString(sign(boundary))['wsTime'], _wsTime(now.subtract(const Duration(seconds: 300))));
      final expired = code(r'$0$1$2$3', wsTimeFromNow: const Duration(seconds: -301));
      expect(() => sign(expired), fails(HuyaSignFailureKind.expired));
    });

    test('a query without fm is returned unchanged and does not advance the clock', () {
      final clock = HuyaSignClock();
      for (final token in ['', 'wsSecret=signed&wsTime=6b49d278&ctype=huya_live&t=100', 'fm=&wsTime=1']) {
        expect(sign(token, clock: clock), token);
      }
      expect(clock.next(now), now.millisecondsSinceEpoch);
      expect(HuyaSign.hasTemplate('a=1&fm=x'), isTrue);
      expect(HuyaSign.hasTemplate('a=1&fm='), isFalse);
      expect(HuyaSign.hasTemplate('xfm=1'), isFalse);
    });

    test('seqid is strictly increasing per clock, so concurrent opens differ (REG-HUYA-007)', () {
      final clock = HuyaSignClock();
      final antiCode = code(r'prefix_$0_$1_$2_$3');
      final signed = [for (var i = 0; i < 64; i++) Uri.splitQueryString(sign(antiCode, clock: clock))];
      final seqIds = [for (final query in signed) int.parse(query['seqid']!)];
      for (var i = 1; i < seqIds.length; i++) {
        expect(seqIds[i], seqIds[i - 1] + 1);
      }
      expect(signed.map((query) => query['wsSecret']).toSet(), hasLength(64));
      expect(signed.map((query) => query['wsTime']).toSet(), hasLength(1));
      // The wall clock wins once it moves past the counter; it never goes back.
      expect(clock.next(now.add(const Duration(seconds: 1))), now.millisecondsSinceEpoch + 1000);
      expect(clock.next(now), now.millisecondsSinceEpoch + 1001);
      expect(identical(HuyaSignClock.process, HuyaSignClock.process), isTrue);
    });

    test('§8 viewer identity helpers', () {
      expect(HuyaSign.viewerUidFromCookie('foo=1; yyuid=1400123456789; bar=2'), 1400123456789);
      expect(HuyaSign.viewerUidFromCookie('foo=yyuid=12; bar=2'), isNull);
      expect(HuyaSign.viewerUidFromCookie('yyuid=0'), isNull);
      expect(HuyaSign.viewerUidFromCookie(null), isNull);
      final random = Random(9);
      for (var i = 0; i < 100; i++) {
        expect(HuyaSign.fallbackViewerUid(random), inInclusiveRange(1400000000000, 1400000000000 + 99999999999));
      }
      expect(HuyaSign.guid(random), matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('§6.2 Tars/WUP codec (legacy BaseTarsHttp vectors)', () {
    test('native getCdnTokenInfoEx request', () {
      final bytes = HuyaCdnTokenCall.request(
        flvUrl: '',
        streamName: _vectorStream,
        userId: const HuyaUserId(huyaUa: 'pc_exe&7060000&official'),
      );
      expect(
        bytes,
        _hex(
          '0000009210032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d0000650800010604745265711d'
          '0000580a0600162837383934313936392d323535393436313539332d31303939323830333833373330333036323532382c3a'
          '0c16002600361770635f6578652637303630303030266f6666696369616c46005c660076000b40420b8c980ca80c',
        ),
      );
    });

    test('web getCdnTokenInfoEx request, short and long (string4) cookie', () {
      const cookie = 'yyuid=1400123456789; foo=bar';
      HuyaUserId viewer(String cookie) =>
          HuyaUserId(uid: 1400123456789, guid: 'fixture-guid', huyaUa: 'webh5&0.1.0&websocket', cookie: cookie);
      expect(
        HuyaCdnTokenCall.request(
          flvUrl: 'https://tx.flv.huya.com/src',
          streamName: 'stream-name',
          userId: viewer(cookie),
        ),
        _hex(
          '000000c010032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d000100920800010604745265711d'
          '000100840a061b68747470733a2f2f74782e666c762e687579612e636f6d2f737263160b73747265616d2d6e616d652c3a03'
          '00000145fddc7d15160c666978747572652d6775696426003615776562683526302e312e3026776562736f636b6574461c79'
          '797569643d313430303132333435363738393b20666f6f3d6261725c660076000b40420b8c980ca80c',
        ),
      );
      final longCookie = 'yyuid=1400123456789; ${List.filled(40, 'k=v123').join('; ')}';
      final long = HuyaCdnTokenCall.request(
        flvUrl: 'https://al.flv.huya.com/src',
        streamName: 'stream-name',
        userId: viewer(longCookie),
      );
      final cookieHex = [for (final byte in utf8.encode(longCookie)) byte.toRadixString(16).padLeft(2, '0')].join();
      expect(
        long,
        _hex(
          '000001fa10032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d000101cc080001060474526571'
          '1d000101be0a061b68747470733a2f2f616c2e666c762e687579612e636f6d2f737263160b73747265616d2d6e616d652c3a'
          '0300000145fddc7d15160c666978747572652d6775696426003615776562683526302e312e3026776562736f636b65744700'
          '000153${cookieHex}5c660076000b40420b8c980ca80c',
        ),
      );
    });

    test('getCdnTokenInfoEx responses: token and expiry; a signed int8 return code', () {
      final ok = HuyaCdnTokenCall.response(
        _hex(
          '0000009810032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d00006b08000206001d0000010c06'
          '04745273701d0000570a065077735365637265743d61626326777354696d653d366162613337303126666d3d63484a6c5a6d'
          '6c345879517758795178587951795879517a2663747970653d687579615f70635f65786526743d31303011012c0b8c980ca80c',
        ),
      );
      expect(ok.code, 0);
      expect(ok.token, 'wsSecret=abc&wsTime=6aba3701&fm=cHJlZml4XyQwXyQxXyQyXyQz&ctype=huya_pc_exe&t=100');
      expect(ok.expireTime, 300);
      final refused = HuyaCdnTokenCall.response(
        _hex(
          '0000004710032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d00001a08000206001d00000200fd'
          '0604745273701d0000050a06001c0b8c980ca80c',
        ),
      );
      // Legacy read int8 as unsigned (253); Tars int8 is signed.
      expect(refused.code, -3);
      expect(refused.token, isEmpty);
    });

    test('packets round-trip; truncated or foreign bytes are FormatException', () {
      final packet = WupPacket(
        servant: 'wupui',
        function: 'f',
        params: {'tReq': WupPacket.intParam(70000), 'x': WupPacket.structParam((w) => w.writeInt(20, -5))},
      ).encode();
      final decoded = WupPacket.decode(packet);
      expect((decoded.servant, decoded.function), ('wupui', 'f'));
      expect(TarsStruct.decode(decoded.params['tReq']!).integer(0), 70000);
      expect(TarsStruct.decode(decoded.params['x']!).struct(0)!.integer(20), -5);
      for (final bad in [packet.sublist(0, packet.length - 3), Uint8List(3), utf8.encode('<html>')]) {
        expect(() => HuyaCdnTokenCall.response(bad), throwsFormatException);
      }
    });
  });

  group('catalog, lists and search (replay)', () {
    test('categories: the four bussLive trees in platform order', () async {
      final samples = ['S01-buss1', 'S01-buss2', 'S01-buss8', 'S01-buss3'];
      final http = _Http([for (final name in samples) _sample(name)]);
      final categories = await _site(http).categories();
      expect(categories.map((category) => category.id), ['1', '2', '8', '3']);
      for (final (index, category) in categories.indexed) {
        final fixture = Fixture.load('huya', samples[index]);
        final expected = HuyaParse.category(fixture.body, id: category.id);
        expect(category.areas.map((area) => area.id), expected.areas.map((area) => area.id));
        expect(category.areas, isNotEmpty);
      }
      expect(http.requests.map((request) => request.url.queryParameters['bussType']), ['1', '2', '8', '3']);
    });

    test('categories: one failed request fails the whole tree (§2.1)', () async {
      final broken = ReplaySample(
        method: 'GET',
        url: Uri.parse('https://live.cdn.huya.com/liveconfig/game/bussLive?bussType=3'),
        status: 502,
        bytes: const [],
      );
      final http = _Http([_sample('S01-buss1'), _sample('S01-buss2'), _sample('S01-buss8'), broken]);
      await expectLater(_site(http).categories(), throwsA(isA<NetworkFailure>()));
    });

    test('area rooms and recommended: page cursors, end rules, headers, no cookie', () async {
      final vault = MemoryCookieVault()..set('huya', 'yyuid=1400123456789; secret=x');
      final http = _Http([
        for (final name in ['S03-hot-page1', 'S03-hot-page2', 'S03-cold-page1', 'S02-page1', 'S02-last', 'S02-beyond'])
          _sample(name),
      ]);
      final site = _site(http, cookies: vault);
      const hot = Area(id: '1', name: '英雄联盟', categoryId: '1');
      final first = await site.areaRooms(hot);
      expect(first.items, hasLength(120));
      expect(first.next, const PageCursor('2'));
      final second = await site.areaRooms(hot, cursor: first.next);
      expect(second.next, const PageCursor('3'));
      final cold = await site.areaRooms(const Area(id: '1579', name: '', categoryId: '2'));
      expect(cold.items, hasLength(1));
      expect(cold.isLast, isTrue, reason: 'totalPage 1');

      final recommended = await site.recommended();
      expect(recommended.next, const PageCursor('2'));
      expect(recommended.items.first.audience.online, isNull, reason: 'totalCount is popularity');
      final last = await site.recommended(cursor: const PageCursor('73'));
      expect(last.items, hasLength(24));
      expect(last.isLast, isTrue);
      final beyond = await site.recommended(cursor: const PageCursor('74'));
      expect(beyond.items, isEmpty);
      expect(beyond.isLast, isTrue);

      final area = http.requests.first;
      expect(area.url.queryParameters, containsPair('gameId', '1'));
      expect(area.headers['user-agent'], _mobileUserAgent);
      expect(area.headers.containsKey('origin'), isFalse);
      final list = http.requests[3];
      expect(list.url.queryParameters.containsKey('gameId'), isFalse);
      expect(list.headers, containsPair('origin', 'https://www.huya.com'));
      expect(list.headers, containsPair('referer', 'https://www.huya.com/'));
      expect(http.requests.every((request) => !request.headers.containsKey('cookie')), isTrue);
    });

    test('search: page 1, page 2 without the repeated first page, the last page, empty results', () async {
      final http = _Http([
        for (final name in ['S04-results', 'S04-page2', 'S04-fallback', 'S04-empty']) _sample(name),
      ]);
      final site = _site(http);
      final first = await site.search('英雄联盟');
      expect(first.items, hasLength(20));
      expect(first.next, const PageCursor('20'));
      final second = await site.search('英雄联盟', cursor: first.next);
      expect(second.items, hasLength(20), reason: 'the response repeats page 1 (40 docs); v4 drops it');
      expect(second.next, const PageCursor('40'));
      final firstRooms = first.items.map((room) => room.ref).toSet();
      expect(second.items.where((room) => firstRooms.contains(room.ref)), isEmpty);

      final fallback = await site.search(Fixture.load('huya', 'S04-fallback').url.queryParameters['q']!);
      expect(fallback.items, hasLength(15));
      expect(fallback.isLast, isTrue, reason: 'numFound 15');
      final empty = await site.search(Fixture.load('huya', 'S04-empty').url.queryParameters['q']!);
      expect(empty.items, isEmpty);
      expect(empty.isLast, isTrue);

      final sent = http.requests.length;
      expect((await site.search('   ')).items, isEmpty);
      expect(http.requests, hasLength(sent), reason: 'a blank keyword is not sent');
      expect(http.requests.map((request) => request.url.queryParameters['start']), ['0', '20', '0', '0']);
      expect(http.requests.first.url.queryParameters, {
        'm': 'Search',
        'do': 'getSearchContent',
        'q': '英雄联盟',
        'uid': '0',
        'v': '4',
        'typ': '-5',
        'livestate': '0',
        'rows': '20',
        'start': '0',
      });
    });
  });

  group('detail (replay)', () {
    test('live, offline and replay; profileRoom bypasses the cache and carries no cookie', () async {
      final vault = MemoryCookieVault()..set('huya', 'yyuid=1400123456789');
      final http = _Http([
        for (final name in ['S05-multicdn', 'S06-off', 'S06-replay']) _sample(name),
      ]);
      final site = _site(http, cookies: vault);
      final live = await site.detail(RoomRef('huya', '660000'));
      expect(live.state, LiveState.live);
      expect(live.ref, RoomRef('huya', '660000'));
      expect(live.card.audience, const Audience(popularity: 448780));
      expect(live.danmakuKeys['uid'], '$_presenter');
      expect((await site.detail(RoomRef('huya', '441195'))).state, LiveState.offline);
      expect((await site.detail(RoomRef('huya', '102411'))).state, LiveState.replay);

      final request = http.requests.first;
      expect(request.url.queryParameters['_'], '${_now.millisecondsSinceEpoch}');
      expect(request.url.queryParameters['showSecret'], '1');
      expect(request.headers, containsPair('cache-control', 'no-cache'));
      expect(request.headers, containsPair('pragma', 'no-cache'));
      expect(request.headers, containsPair('origin', 'https://www.huya.com'));
      expect(request.headers.containsKey('cookie'), isFalse);
    });

    test('status 422 is NotFound: a missing room and a letter alias (S06)', () async {
      final http = _Http([_sample('S06-notfound'), _sample('S06-alias')]);
      final site = _site(http);
      await expectLater(site.detail(RoomRef('huya', '999999999')), throwsA(isA<NotFound>()));
      await expectLater(site.detail(RoomRef('huya', 'lpl')), throwsA(isA<NotFound>()));
    });
  });

  group('streams', () {
    final nativeToken = 'wsTime=6aba3701&fm=${_fm(_nativeTemplate)}&ctype=huya_pc_exe&t=100';

    test('S05-multicdn: native FLV on every CDN, then web-signed HLS; WUP per stream name, never for HLS', () async {
      final http = _Http(
        [_patched('S05-multicdn', antiCode: _withTemplate)],
        wup: (request, _) => _wupAnswer(request, token: nativeToken, expireTime: 300),
        login: (request) => _loginAnswer(request, _viewer),
      );
      final site = _site(http);
      final set = await site.streams(_room('660000'));

      expect(set.qualities.map((quality) => quality.id), ['0', '4000', '2000', '500']);
      expect(set.selected.id, '0', reason: 'best quality when none is requested');
      expect(set.lines.map((line) => '${line.format.name}:${line.lineId}'), [
        for (final format in ['flv', 'hls'])
          for (final cdn in ['AL', 'TX', 'HS', 'TX15', 'HS24']) '$format:$cdn',
      ]);
      for (final line in set.lines) {
        expect(line.url.scheme, 'https');
        expect(line.url.queryParameters['codec'], '264');
        expect(line.url.queryParameters.containsKey('ratio'), isFalse, reason: 'source quality');
        expect(line.requested.id, '0');
        expect(line.confirmed, isNull, reason: 'Huya does not report the delivered quality');
        expect(line.codec, 'avc');
        expect(line.headers, HuyaParse.mediaHeaders('660000'));
      }

      final flv = set.lines.where((line) => line.format == StreamFormat.flv);
      for (final line in flv) {
        expect(HuyaParse.isNativeFlv(line.url), isTrue);
        expect(line.url.path, endsWith('.flv'));
        _expectSigned(line.url, _nativeTemplate, uid: _presenter);
        expect(line.url.queryParameters['wsTime'], '6aba3701', reason: 'never extended');
        // iExpireTime 300 s after receipt is earlier than wsTime + 300 s.
        expect(line.lease!.cutsConnection, isFalse);
        expect(line.lease!.expiresAt, _now.add(const Duration(seconds: 300)));
        expect(line.lease!.refreshAt, _now.add(const Duration(seconds: 270)));
      }
      final al = flv.first.url;
      expect(
        al.toString(),
        'https://al-game.flv.huya.com/src/$_stream1.flv?wsTime=6aba3701&ctype=huya_pc_exe&t=100'
        '&wsSecret=${al.queryParameters['wsSecret']}&seqid=${al.queryParameters['seqid']}&ver=1&fs=bgct'
        '&u=1134703440&codec=264',
      );

      for (final line in set.lines.where((line) => line.format == StreamFormat.hls)) {
        expect(line.url.path, endsWith('.m3u8'));
        expect(line.url.queryParameters, containsPair('ctype', 'tars_mp'));
        expect(line.url.queryParameters, containsPair('t', '102'));
        _expectSigned(line.url, _webTemplate, uid: _viewer);
        final issuedAt = DateTime.fromMillisecondsSinceEpoch(_millis(line.url), isUtc: true);
        expect(line.lease!.cutsConnection, isTrue);
        expect(line.lease!.refreshAt, issuedAt.add(const Duration(seconds: 100)));
        expect(line.lease!.expiresAt, issuedAt.add(const Duration(seconds: 125)));
      }

      // Ten signatures, ten distinct deterministic milliseconds.
      expect(set.lines.map((line) => _millis(line.url)).toSet(), {
        for (var i = 0; i < 10; i++) _now.millisecondsSinceEpoch + i,
      });

      final wups = http.on('wup.huya.com');
      expect(wups, hasLength(2), reason: 'AL/TX/HS and TX15/HS24 share a stream name');
      expect(wups.first.body, _hex(_nativeRequestStream1), reason: 'byte for byte the legacy native request');
      final requested = <String>{};
      for (final request in wups) {
        final tReq = TarsStruct.decode(WupPacket.decode(request.body!).params['tReq']!).struct(0)!;
        requested.add(tReq.string(1)!);
        expect(tReq.string(0), isEmpty);
        expect(tReq.integer(4), 66);
        expect(tReq.struct(3)!.integer(0), 0, reason: 'no viewer UID');
        expect(tReq.struct(3)!.string(4), isEmpty, reason: 'no cookie');
        expect(request.headers, {
          'origin': 'https://www.huya.com',
          'referer': 'https://www.huya.com/',
          'user-agent': HuyaParse.mediaUserAgent,
          'content-type': 'application/x-wup',
        });
        expect(request.timeout, const Duration(seconds: 8));
      }
      expect(requested, {_stream1, _stream2});

      final logins = http.on('udblgn.huya.com');
      expect(logins, hasLength(1), reason: 'one anonymous login shared by every HLS line');
      expect(jsonDecode(utf8.decode(logins.single.body!)), {
        'appId': 5002,
        'byPass': 3,
        'context': '',
        'version': '2.4',
        'data': <String, Object?>{},
      });
      expect(site.nativeFallbacks, 0);
      expect(site.degradedViewers, 0);
    });

    test('a selected quality sets ratio on every line; an unknown one falls back to the best', () async {
      final http = _Http(
        [_patched('S05-multicdn', antiCode: _withTemplate)],
        wup: (request, _) => _wupAnswer(request, token: nativeToken, expireTime: 300),
        login: (request) => _loginAnswer(request, _viewer),
      );
      final site = _site(http);
      final set = await site.streams(
        _room('660000'),
        quality: const Quality(id: '2000', label: '', rank: 0),
      );
      expect(set.selected.label, '超清');
      expect(set.lines.map((line) => line.url.queryParameters['ratio']).toSet(), {'2000'});
      expect(set.lines.every((line) => line.requested.id == '2000'), isTrue);
      final unknown = await site.streams(
        _room('660000'),
        quality: const Quality(id: '9999', label: '', rank: 0),
      );
      expect(unknown.selected.id, '0');
    });

    test('native WUP down: the web FLV is signed as the account; one line equals the legacy vector', () async {
      final vault = MemoryCookieVault()..set('huya', 'foo=1; yyuid=$_presenter; bar=2');
      final http = _Http([
        _patched('S05-multicdn', antiCode: _withTemplate, flv: {'AL'}, hls: {}),
      ], wup: (request, _) => throw const TransportFailure('huya', TransportReason.timeout));
      final site = _site(http, cookies: vault);
      final line = (await site.streams(_room('660000'))).lines.single;
      expect(
        line.url.toString(),
        'https://al-game.flv.huya.com/src/$_stream1.flv?wsTime=6aba3701&ctype=tars_mp&fs=bgct&t=102'
        '&wsSecret=dacbea4ab2bb0c07f5c99e3c6ecf8874&seqid=1791848882565&ver=1&u=1134703440&codec=264',
      );
      expect(HuyaParse.isNativeFlv(line.url), isFalse);
      expect(line.lease!.cutsConnection, isTrue);
      expect(line.lease!.refreshAt, _now.add(const Duration(seconds: 100)));
      expect(line.lease!.expiresAt, _now.add(const Duration(seconds: 125)));
      expect(line.headers.containsKey('cookie'), isFalse, reason: 'no cookie to the CDN');
      expect(site.nativeFallbacks, 1);
      expect(http.on('udblgn.huya.com'), isEmpty, reason: 'the cookie yyuid is the viewer');
    });

    test('native refused and room template unusable: web getCdnTokenInfoEx as the viewer; HLS dropped', () async {
      const cookie = 'yyuid=$_viewer; other=x';
      final vault = MemoryCookieVault()..set('huya', cookie);
      final webToken = 'wsTime=6aba3701&fm=${_fm(_webTemplate)}&ctype=huya_webh5&t=100';
      final http = _Http(
        [_sample('S05-multicdn')],
        wup: (request, tReq) => tReq.struct(3)!.string(3) == 'pc_exe&7060000&official'
            ? _wupAnswer(request, code: -1)
            : _wupAnswer(request, token: webToken, expireTime: 60),
      );
      final site = _site(http, cookies: vault);
      final set = await site.streams(_room('660000'));
      // The recorded fm is scrubbed: FLV recovers through web WUP, HLS has no fallback.
      expect(set.lines.map((line) => '${line.format.name}:${line.lineId}'), [
        for (final cdn in ['AL', 'TX', 'HS', 'TX15', 'HS24']) 'flv:$cdn',
      ]);
      for (final line in set.lines) {
        _expectSigned(line.url, _webTemplate, uid: _viewer);
        expect(line.url.queryParameters['ctype'], 'huya_webh5');
        // Web family, bounded by the web token: refresh 30 s before its 60 s.
        expect(line.lease!.cutsConnection, isTrue);
        expect(line.lease!.refreshAt, _now.add(const Duration(seconds: 30)));
        expect(line.lease!.expiresAt, _now.add(const Duration(seconds: 60)));
      }
      final web = [
        for (final request in http.on('wup.huya.com'))
          if (TarsStruct.decode(WupPacket.decode(request.body!).params['tReq']!).struct(0)!.struct(3)!.string(3) ==
              'webh5&0.1.0&websocket')
            request,
      ];
      expect(web, hasLength(5), reason: 'one per viewer, line and stream');
      final bases = <String>{};
      for (final request in web) {
        final tReq = TarsStruct.decode(WupPacket.decode(request.body!).params['tReq']!).struct(0)!;
        bases.add('${tReq.string(0)} ${tReq.string(1)}');
        expect(tReq.integer(2), 0);
        expect(tReq.integer(4), 66);
        final tId = tReq.struct(3)!;
        expect(tId.integer(0), _viewer);
        expect(tId.string(1), matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(tId.string(2), isEmpty);
        expect(tId.string(4), cookie);
        expect(tId.integer(5), 0);
        expect(request.headers['cookie'], cookie);
        expect(request.headers['user-agent'], _mobileUserAgent);
      }
      expect(bases, {
        'https://al-game.flv.huya.com/src $_stream1',
        'https://tx.flv.huya.com/src $_stream1',
        'https://hs.flv.huya.com/src $_stream1',
        'https://tx.flv.huya.com/src $_stream2',
        'https://hs.flv.huya.com/src $_stream2',
      });
      expect(http.on('wup.huya.com').length - web.length, 2, reason: 'native requests per stream name');
      expect(site.nativeFallbacks, 5);
    });

    test(
      'no line opens: structural → ApiChanged, empty tokens → StreamUnavailable, network → NetworkFailure',
      () async {
        final refusing = _Http([_sample('S05-multicdn')], wup: (request, _) => _wupAnswer(request, code: -1));
        final vault = MemoryCookieVault()..set('huya', 'yyuid=$_viewer');
        await expectLater(_site(refusing, cookies: vault).streams(_room('660000')), throwsA(isA<ApiChanged>()));

        final empty = _Http([
          _patched('S05-multicdn', antiCode: (_) => ''),
        ], wup: (request, _) => _wupAnswer(request, code: -1));
        await expectLater(_site(empty).streams(_room('660000')), throwsA(isA<StreamUnavailable>()));

        final unreachable = _Http([
          _patched('S05-multicdn', hls: {}),
        ], wup: (request, _) => throw const TransportFailure('huya', TransportReason.connect));
        await expectLater(_site(unreachable, cookies: vault).streams(_room('660000')), throwsA(isA<NetworkFailure>()));
      },
    );

    test('an expired AntiCode re-requests profileRoom once; still expired is ApiChanged', () async {
      final vault = MemoryCookieVault()..set('huya', 'yyuid=$_viewer');
      final stale = _wsTime(_now.subtract(const Duration(seconds: 400)));
      String expire(String antiCode) => _withTemplate(antiCode).replaceFirst('wsTime=6aba3701', 'wsTime=$stale');
      final expired = _patched('S05-multicdn', antiCode: expire, flv: {}, hls: {'AL'});

      final always = _Http([expired]);
      await expectLater(_site(always, cookies: vault).streams(_room('660000')), throwsA(isA<ApiChanged>()));
      expect(always.on('mp.huya.com'), hasLength(2));

      final fresh = _patched('S05-multicdn', antiCode: _withTemplate, flv: {}, hls: {'AL'});
      final recovered = _Http(const [], profiles: [expired, fresh]);
      final set = await _site(recovered, cookies: vault).streams(_room('660000'));
      expect(set.lines.single.url.queryParameters['wsTime'], '6aba3701');
      expect(recovered.on('mp.huya.com'), hasLength(2));
    });

    test('rooms without a stream: offline, replay, rateArray without multiLine; a missing room', () async {
      final http = _Http([
        for (final name in ['S06-off', 'S06-replay', 'S05-ratearray', 'S06-notfound']) _sample(name),
      ]);
      final site = _site(http);
      for (final roomId in ['441195', '102411', '30925595']) {
        await expectLater(site.streams(_room(roomId)), throwsA(isA<StreamUnavailable>()), reason: roomId);
      }
      await expectLater(site.streams(_room('999999999')), throwsA(isA<NotFound>()));
      expect(http.on('wup.huya.com'), isEmpty);
    });

    test('anonymous login failing signs with a temporary UID, not cached; the next open retries', () async {
      var attempts = 0;
      final http = _Http(
        [
          _patched('S05-multicdn', antiCode: _withTemplate, flv: {}, hls: {'AL', 'TX'}),
        ],
        login: (request) {
          if (++attempts == 1) throw const TransportFailure('huya', TransportReason.connect);
          return _loginAnswer(request, _viewer);
        },
      );
      final site = _site(http);
      final degraded = await site.streams(_room('660000'));
      final temporary = HuyaParse.unrotateUid(int.parse(degraded.lines.first.url.queryParameters['u']!));
      expect(temporary, inInclusiveRange(1400000000000, 1499999999999));
      expect(temporary, isNot(_viewer));
      expect(degraded.lines.map((line) => line.url.queryParameters['u']).toSet(), hasLength(1));
      expect(site.degradedViewers, 1);
      expect(http.on('udblgn.huya.com'), hasLength(1), reason: 'one attempt per open');

      final official = await site.streams(_room('660000'));
      expect(official.lines.first.url.queryParameters['u'], '${HuyaParse.rotateUid(_viewer)}');
      await site.streams(_room('660000'));
      expect(http.on('udblgn.huya.com'), hasLength(2), reason: 'the official UID is cached');
    });

    test('concurrent play and record share one native request but get different signatures (REG-HUYA-007)', () async {
      final http = _Http([
        _patched('S05-multicdn', antiCode: _withTemplate, flv: {'AL'}, hls: {}),
      ], wup: (request, _) => _wupAnswer(request, token: nativeToken, expireTime: 300));
      final site = _site(http);
      final (play, record) = await (site.streams(_room('660000')), site.streams(_room('660000'))).wait;
      final a = play.lines.single.url.queryParameters;
      final b = record.lines.single.url.queryParameters;
      expect(a['seqid'], isNot(b['seqid']));
      expect(a['wsSecret'], isNot(b['wsSecret']));
      expect(a['wsTime'], b['wsTime']);
      expect(http.on('wup.huya.com'), hasLength(1), reason: 'same stream name at the same time');
      expect(http.on('mp.huya.com'), hasLength(2), reason: 'every open re-requests profileRoom');
    });
  });

  group('§1 links', () {
    test('numbers, room pages, share text, other hosts and reserved paths', () async {
      final site = _site(_Http(const []));
      final room = RoomRef('huya', '660000');
      for (final input in [
        '660000',
        ' https://www.huya.com/660000 ',
        'https://m.huya.com/660000?from=share',
        'https://huya.com/660000/',
        '快来看 https://www.huya.com/660000，好看',
        'www.huya.com/660000',
      ]) {
        expect(await site.resolve(input), room, reason: input);
      }
      for (final input in [
        'https://www.huya.com.example/660000',
        'huya.com.example/660000',
        'https://live.bilibili.com/6',
        'https://www.huya.com/g/lol',
        'https://www.huya.com/',
        'https://www.huya.com/a.b',
        '0',
        'hello',
      ]) {
        expect(await site.resolve(input), isNull, reason: input);
      }
    });

    test('a letter alias is looked up on its room page (profileRoom refuses it, S06-alias)', () async {
      ReplaySample page(String path, String html, {int status = 200}) => ReplaySample(
        method: 'GET',
        url: Uri.parse('https://www.huya.com/$path'),
        status: status,
        bytes: utf8.encode(html),
      );
      final http = _Http([
        page(
          'lpl',
          '<script>var TT_ROOM_DATA = {"type":"NORMAL","state":"ON","privateHost":"lpl", '
              '"profileRoom":"660000","gid":1};\nvar TT_PROFILE_INFO = {};</script>',
        ),
        page('loose', '<script>window.x = {"profileRoom":880351};</script>'),
        page('nobody', '<html>没有找到该房间</html>'),
        page('gone', '', status: 404),
      ]);
      final site = _site(http);
      expect(await site.resolve('https://www.huya.com/lpl'), RoomRef('huya', '660000'));
      expect(await site.resolve('https://m.huya.com/loose'), RoomRef('huya', '880351'));
      await expectLater(site.resolve('https://www.huya.com/nobody'), throwsA(isA<NotFound>()));
      await expectLater(site.resolve('https://www.huya.com/gone'), throwsA(isA<NotFound>()));
      expect(http.requests.first.headers['user-agent'], startsWith('Mozilla/5.0 (Windows'));
    });
  });
}
