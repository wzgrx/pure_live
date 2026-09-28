import 'dart:convert';

import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

void main() {
  group('query', () {
    test('parameters are appended and the existing query is kept byte for byte', () {
      final signed = Uri.parse('https://cdn.test/live.flv?wsSecret=a%2Bb&t=1');
      final url = LiveRequest.withQuery(signed, const {'uid': 7, 'name': '斗鱼 直播'});
      expect(url.query, 'wsSecret=a%2Bb&t=1&uid=7&name=%E6%96%97%E9%B1%BC+%E7%9B%B4%E6%92%AD');
    });

    test('null values are left out, iterables repeat, an empty query changes nothing', () {
      final base = Uri.parse('https://api.test/list');
      expect(identical(LiveRequest.withQuery(base, const {'a': null}), base), isTrue);
      expect(
        LiveRequest.withQuery(base, const {
          'id': [1, 2],
          'skip': null,
        }).query,
        'id=1&id=2',
      );
    });

    test('GET carries query, headers, timeout and cancellation', () {
      final cancel = CancelToken();
      final request = LiveRequest.get(
        site: 'huya',
        url: Uri.parse('https://api.test/room'),
        query: const {'roomId': '11342412'},
        headers: const {'referer': 'https://www.huya.com/'},
        timeout: const Duration(seconds: 3),
        cancel: cancel,
      );
      expect(request.method, 'GET');
      expect(request.url.query, 'roomId=11342412');
      expect(request.headers['referer'], 'https://www.huya.com/');
      expect(request.timeout, const Duration(seconds: 3));
      expect(request.cancel, same(cancel));
    });
  });

  test("the default timeout is 3.x's 20 seconds", () {
    expect(LiveRequest(site: 'x', url: Uri.parse('https://x.test')).timeout, const Duration(seconds: 20));
  });

  test('form bodies are percent-encoded and typed', () {
    final request = LiveRequest.form(
      site: 'douyu',
      url: Uri.parse('https://www.douyu.com/lapi/live/getH5Play/1'),
      fields: const {'enc_data': 'a+b/c=', 'rate': '-1'},
    );
    expect(request.method, 'POST');
    expect(utf8.decode(request.body!), 'enc_data=a%2Bb%2Fc%3D&rate=-1');
    expect(request.headers['content-type'], 'application/x-www-form-urlencoded; charset=utf-8');
  });

  test('JSON bodies are UTF-8 JSON and typed', () {
    final request = LiveRequest.json(
      site: 'twitch',
      url: Uri.parse('https://gql.twitch.tv/gql'),
      json: const {'query': '直播', 'n': 1},
    );
    expect(request.method, 'POST');
    expect(jsonDecode(utf8.decode(request.body!)), {'query': '直播', 'n': 1});
    expect(request.headers['content-type'], 'application/json; charset=utf-8');
  });

  test('a response decodes JSON whatever its content type says', () {
    final response = LiveResponse(
      status: 200,
      bytes: utf8.encode('{"ok":true}'),
      url: Uri.parse('https://x.test'),
      headers: const {
        'content-type': ['json;charset=utf-8'],
      },
    );
    expect(response.json, {'ok': true});
    expect(
      () => LiveResponse(status: 200, bytes: utf8.encode('<html>'), url: Uri.parse('https://x.test')).json,
      throwsFormatException,
    );
  });
}
