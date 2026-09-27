import 'dart:convert';
import 'dart:io';

import 'package:live_cli/live_cli.dart';
import 'package:test/test.dart';

const _rules = ScrubRules(
  jsonKeys: {'did': ScrubRule.secret, 'uid': ScrubRule.person, 'nn': ScrubRule.person},
  queryParams: {'wsSecret': ScrubRule.secret, 'did': ScrubRule.secret},
);

void main() {
  test('secrets keep their shape; people map consistently', () {
    final scrubber = Scrubber(_rules, seed: 1);
    final json =
        scrubber.scrubJson({
              'did': '10000000000000000000000000000001',
              'list': [
                {'uid': 123456789, 'nn': '直播观众甲'},
                {'uid': 123456789, 'nn': '直播观众甲'},
                {'uid': 987654321, 'nn': 'viewer_B'},
              ],
              'room': {'title': '公开标题', 'rid': 5526219},
            })!
            as Map<String, Object?>;

    final did = json['did']! as String;
    expect(did, hasLength(32));
    expect(did, matches(RegExp(r'^\d+$')));
    expect(did, isNot('10000000000000000000000000000001'));

    final list = (json['list']! as List).cast<Map<String, Object?>>();
    expect(list[0]['uid'], list[1]['uid']);
    expect(list[0]['uid'], isNot(list[2]['uid']));
    expect(list[0]['uid'], isA<int>());
    expect(list[0]['nn'], '观众1');
    expect(list[2]['nn'], hasLength('viewer_B'.length));
    expect((json['room']! as Map)['title'], '公开标题', reason: 'public room data is kept');
    expect((json['room']! as Map)['rid'], 5526219);
  });

  test('URL signatures are replaced but expiry parameters stay', () {
    final scrubber = Scrubber(_rules, seed: 2);
    const url =
        'https://hw-tct.douyucdn.cn/live/abc.flv?wsSecret=0123456789abcdef&wsTime=66f6a0b0&expire=1727400000&did=aa11';
    final scrubbed = scrubber.scrubQuery(url);
    final query = Uri.parse(scrubbed).queryParameters;
    expect(query['wsTime'], '66f6a0b0');
    expect(query['expire'], '1727400000');
    expect(query['wsSecret'], hasLength(16));
    expect(query['wsSecret'], isNot('0123456789abcdef'));
    expect(scrubber.leaks(scrubbed), isEmpty);
  });

  test('embedded JSON strings and HTML scripts are scrubbed', () {
    final scrubber = Scrubber(_rules, seed: 3);
    final embedded =
        scrubber.scrubJson({
              'data': jsonEncode({'did': 'abcdef123456'}),
            })!
            as Map;
    expect(embedded['data'], isNot(contains('abcdef123456')));

    const html = r'<script>window.x={"uid":"55667788","nn":"主播粉丝"};var y="{\"did\":\"fedcba654321\"}"</script>';
    final text = scrubber.scrubText(html);
    expect(text, isNot(contains('55667788')));
    expect(text, isNot(contains('主播粉丝')));
    expect(text, isNot(contains('fedcba654321')));
    expect(text, startsWith('<script>window.x={"uid":"'));
    expect(scrubber.leaks(text), isEmpty);
  });

  test('cookie headers keep names and lose values', () {
    final scrubber = Scrubber(_rules, seed: 4);
    final cookie = scrubber.scrubCookieHeader('dy_did=0123456789abcdef; acf_auth=SECRETSECRET');
    expect(cookie, startsWith('dy_did='));
    expect(cookie, contains('; acf_auth='));
    expect(scrubber.leaks(cookie), isEmpty);
    final setCookie = scrubber.scrubSetCookie('LTP0=TOKENVALUE123; Path=/; HttpOnly');
    expect(setCookie, endsWith('; Path=/; HttpOnly'));
    expect(setCookie, isNot(contains('TOKENVALUE123')));
  });

  test('writeSample refuses to write when an original survives in the request', () async {
    final temp = await Directory.systemTemp.createTemp('fixture-test');
    addTearDown(() => temp.delete(recursive: true));
    final exchange = RawExchange(
      // The request form repeats the did under a name the rules do not list;
      // request parts are scrubbed by rules only, so this must be refused.
      request: CaptureRequest(
        url: Uri.parse('https://example.test/api?did=abcdef123456'),
        method: 'POST',
        body: 'device=abcdef123456',
      ),
      status: 200,
      headers: const {
        'content-type': ['application/json'],
      },
      body: utf8.encode('{"ok":1}'),
      route: 'direct',
      capturedAt: DateTime.utc(2026, 9, 27),
    );
    await expectLater(
      writeSample(exchange, Scrubber(_rules, seed: 5), directory: temp, platform: 'douyu', sample: 'S01-test'),
      throwsA(isA<LeakException>()),
    );
    expect(temp.listSync(), isEmpty);
  });

  test('a body value under an unlisted key is replaced and noted', () async {
    final temp = await Directory.systemTemp.createTemp('fixture-test');
    addTearDown(() => temp.delete(recursive: true));
    final exchange = RawExchange(
      request: CaptureRequest(url: Uri.parse('https://example.test/api')),
      status: 200,
      headers: const {
        'content-type': ['application/json'],
      },
      body: utf8.encode('{"did":"abcdef123456","other":"abcdef123456"}'),
      route: 'direct',
      capturedAt: DateTime.utc(2026, 9, 27),
    );
    await writeSample(exchange, Scrubber(_rules, seed: 5), directory: temp, platform: 'douyu', sample: 'S01-test');
    final body = jsonDecode(File('${temp.path}/body.json').readAsStringSync()) as Map<String, Object?>;
    expect(body['other'], body['did']);
    expect(body['did'], isNot('abcdef123456'));
    expect(File('${temp.path}/meta.json').readAsStringSync(), contains('body:elsewhere'));
  });

  test('writeSample writes body and meta without secrets', () async {
    final temp = await Directory.systemTemp.createTemp('fixture-test');
    addTearDown(() => temp.delete(recursive: true));
    final exchange = RawExchange(
      request: CaptureRequest(url: Uri.parse('https://example.test/betard/5526219')),
      status: 200,
      headers: const {
        'content-type': ['application/json; charset=utf-8'],
        'set-cookie': ['acf_did=abcdef123456; Path=/', 'other=zzzzzz999999'],
      },
      body: utf8.encode('{"room":{"room_id":5526219,"did":"abcdef123456"}}'),
      route: 'direct',
      capturedAt: DateTime.utc(2026, 9, 27, 8),
    );
    final written = await writeSample(
      exchange,
      Scrubber(_rules, seed: 6),
      directory: temp,
      platform: 'douyu',
      sample: 'S05-live',
    );
    expect(written.bodyFile, 'body.json');
    final meta = jsonDecode(File('${temp.path}/meta.json').readAsStringSync()) as Map<String, Object?>;
    expect(meta['schema'], fixtureSchema);
    expect((meta['raw']! as Map)['length'], exchange.body.length);
    final all = File('${temp.path}/meta.json').readAsStringSync() + File('${temp.path}/body.json').readAsStringSync();
    expect(all, isNot(contains('abcdef123456')));
    expect(all, isNot(contains('zzzzzz999999')));
    expect(all, contains('5526219'));
  });

  test('path rules override key rules; single characters are kept', () {
    final scrubber = Scrubber(
      const ScrubRules(
        jsonKeys: {'uid': ScrubRule.person},
        jsonPaths: {r'$.data.anchor.uid': ScrubRule.keep, r'$.data.list[*].sec': ScrubRule.secret},
      ),
      seed: 7,
    );
    final json =
        scrubber.scrubJson({
              'data': {
                'anchor': {'uid': 12345678},
                'viewer': {'uid': 87654321},
                'list': [
                  {'sec': 'abcdef1234', 'uid': 0},
                ],
              },
            })!
            as Map;
    final data = json['data'] as Map;
    expect((data['anchor'] as Map)['uid'], 12345678);
    expect((data['viewer'] as Map)['uid'], isNot(87654321));
    final item = (data['list'] as List).single as Map;
    expect(item['sec'], isNot('abcdef1234'));
    expect(item['uid'], 0);
  });

  test('HTML-escaped pairs and escaped-ampersand parameters are scrubbed', () {
    final scrubber = Scrubber(_rules, seed: 8);
    // JSON inside HTML writes & as a backslash followed by u0026.
    final amp = '${String.fromCharCode(92)}u0026';
    final html =
        '<div data-value="{&quot;did&quot;:&quot;abcdef123456&quot;}"></div> '
        '<script>{"url":"https://cdn.example.test/a.flv?expire=1${amp}wsSecret=0123456789abcdef${amp}x=1"}</script>';
    final text = scrubber.scrubText(html);
    expect(text, isNot(contains('abcdef123456')));
    expect(text, isNot(contains('0123456789abcdef')));
    expect(text, contains('?expire=1${amp}wsSecret='));
    expect(scrubber.leaks(text), isEmpty);
  });

  test('response headers echoing a request signature get the same synthetic value', () async {
    final temp = await Directory.systemTemp.createTemp('fixture-test');
    addTearDown(() => temp.delete(recursive: true));
    const rules = ScrubRules(
      queryParams: {'w_rid': ScrubRule.secret},
      responseHeaders: {'x-ms-token': ScrubRule.secret, 'bdturing-verify': ScrubRule.secret},
      jsonPaths: {r'$header.bdturing-verify.detail': ScrubRule.secret},
    );
    final exchange = RawExchange(
      request: CaptureRequest(url: Uri.parse('https://api.example.test/info?room=1&w_rid=feedfacecafe0123')),
      status: 200,
      headers: const {
        'content-type': ['application/json'],
        'x-client-sign': ['feedfacecafe0123'],
        'x-ms-token': ['TOKENtoken123456'],
        'bdturing-verify': ['{"detail":"DETAILvalue999","subtype":"whirl"}'],
      },
      body: utf8.encode('{"code":0}'),
      route: 'direct',
      capturedAt: DateTime.utc(2026, 9, 27),
    );
    await writeSample(exchange, Scrubber(rules, seed: 9), directory: temp, platform: 'x', sample: 'S01-echo');
    final meta = File('${temp.path}/meta.json').readAsStringSync();
    final decoded = jsonDecode(meta) as Map<String, Object?>;
    final headers = (decoded['response']! as Map<String, Object?>)['headers']! as Map<String, Object?>;
    final url = (decoded['request']! as Map<String, Object?>)['url']! as String;
    expect(headers['x-client-sign'], Uri.parse(url).queryParameters['w_rid']);
    expect(meta, isNot(contains('feedfacecafe0123')));
    expect(meta, isNot(contains('TOKENtoken123456')));
    expect(meta, isNot(contains('DETAILvalue999')));
    expect(meta, contains('whirl'));
  });

  test('a known value in an unmatched spelling is replaced before the leak check', () async {
    final temp = await Directory.systemTemp.createTemp('fixture-test');
    addTearDown(() => temp.delete(recursive: true));
    final quote = '${String.fromCharCode(92)}"';
    final page =
        '<script>var a={"did":"abcdef123456"};setPageViewLog({"odin":"{${quote}did$quote:${quote}abcdef123456$quote}"});</script>';
    final exchange = RawExchange(
      request: CaptureRequest(url: Uri.parse('https://live.example.test/room')),
      status: 200,
      headers: const {
        'content-type': ['text/html'],
      },
      body: utf8.encode(page),
      route: 'direct',
      capturedAt: DateTime.utc(2026, 9, 27),
    );
    await writeSample(exchange, Scrubber(_rules, seed: 10), directory: temp, platform: 'x', sample: 'S01-page');
    final body = File('${temp.path}/body.html').readAsStringSync();
    expect(body, isNot(contains('abcdef123456')));
    expect(body, contains('setPageViewLog'));
  });

  test('text patterns replace a signature inside a path or a compound value and keep the expiry', () {
    final scrubber = Scrubber(const ScrubRules(textPatterns: {'hmac=([0-9a-f]{16,})': ScrubRule.secret}), seed: 11);
    const master =
        'https://cdn.example.test/a/b_playlist.m3u8?hdnts=st=1790524222~exp=1790585432~hmac=0123456789abcdef0123';
    const variant = '720p/hdntl=exp=1790585609~data=hdntl~hmac=fedcba9876543210fedc/b_chunklist.m3u8';
    final url = scrubber.scrubQuery(master);
    final text = scrubber.scrubText('#EXTM3U\n$variant\n');
    expect(url, contains('exp=1790585432'));
    expect(url, isNot(contains('0123456789abcdef0123')));
    expect(RegExp('hmac=([0-9a-f]+)').firstMatch(url)!.group(1), hasLength(20));
    expect(text, contains('exp=1790585609'));
    expect(text, isNot(contains('fedcba9876543210fedc')));
    expect(scrubber.leaks('$url$text'), isEmpty);
  });

  test('a text pattern replaces its group even when the value also occurs in the context', () {
    final scrubber = Scrubber(
      const ScrubRules(textPatterns: {'DATA-ID="USER-COUNTRY",VALUE="([^"]+)"': ScrubRule.secret}),
      seed: 3,
    );
    final text = scrubber.scrubText('#EXT-X-SESSION-DATA:DATA-ID="USER-COUNTRY",VALUE="US"\n');
    expect(text, startsWith('#EXT-X-SESSION-DATA:DATA-ID="USER-COUNTRY",VALUE="'));
    expect(text, isNot(contains('VALUE="US"')));
  });
}
