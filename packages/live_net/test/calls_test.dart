import 'dart:convert';
import 'dart:io';

import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Uri base;
  late IoLiveHttp http;
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('live_net_calls');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    http = IoLiveHttp();
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/json':
          response
            ..headers.set('content-type', 'json;charset=utf-8')
            ..write(jsonEncode({'query': request.uri.queryParameters, 'probe': request.headers.value('x-probe')}));
        case '/echo':
          final body = await utf8.decoder.bind(request).join();
          response.write(
            jsonEncode({'type': request.headers.contentType?.mimeType, 'body': body, 'query': request.uri.query}),
          );
        case '/forbidden':
          response
            ..statusCode = HttpStatus.forbidden
            ..headers.set('x-request-id', 'req-1')
            ..write('x' * 400);
        case '/file':
          response
            ..contentLength = 12
            ..add(utf8.encode('hello '))
            ..add(utf8.encode('world!'));
        case '/range':
          response
            ..statusCode = HttpStatus.partialContent
            ..write('part');
      }
      await response.close();
    });
  });

  tearDown(() async {
    http.close();
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  test('getText and getJson send query and headers; JSON is decoded whatever the content type', () async {
    final json = await http.getJson(
      'douyu',
      base.resolve('/json'),
      query: const {'rid': 9999},
      headers: const {'x-probe': 'yes'},
    );
    expect(json, {
      'query': {'rid': '9999'},
      'probe': 'yes',
    });
    expect(await http.getText('douyu', base.resolve('/json')), contains('"query"'));
  });

  test('postJson sends a form, a JSON body or nothing', () async {
    final form = (await http.postJson('douyu', base.resolve('/echo'), form: const {'a': '1 2'}))! as Map;
    expect(form['type'], 'application/x-www-form-urlencoded');
    expect(form['body'], 'a=1+2');
    final json = (await http.postJson('twitch', base.resolve('/echo'), json: const {'x': 1}))! as Map;
    expect(json['type'], 'application/json');
    expect(jsonDecode(json['body'] as String), {'x': 1});
    final empty = (await http.postJson('huya', base.resolve('/echo'), query: const {'q': 'v'}))! as Map;
    expect(empty['body'], '');
    expect(empty['query'], 'q=v');
  });

  test('a status that is not 2xx throws HttpStatusFailure with a short body preview and headers', () async {
    await expectLater(
      http.getText('douyu', base.resolve('/forbidden')),
      throwsA(
        isA<HttpStatusFailure>()
            .having((f) => f.status, 'status', 403)
            .having((f) => f.site, 'site', 'douyu')
            .having((f) => f.bodyPreview?.length, 'preview length', 256)
            .having((f) => f.headers['x-request-id'], 'request id', 'req-1'),
      ),
    );
  });

  test('head returns every status', () async {
    final response = await http.head('douyu', base.resolve('/forbidden'));
    expect(response.status, 403);
  });

  group('download', () {
    test('writes through a .part file, reports progress and renames on success', () async {
      final target = '${temp.path}/nested/file.bin';
      final progress = <(int, int?)>[];
      final file = await http.download(
        LiveRequest(site: 'update', url: base.resolve('/file')),
        target,
        onProgress: (received, total) => progress.add((received, total)),
      );
      expect(file.path, target);
      expect(await file.readAsString(), 'hello world!');
      expect(File('$target.part').existsSync(), isFalse);
      expect(progress.last, (12, 12));
    });

    test('206 is accepted', () async {
      final file = await http.download(LiveRequest(site: 'update', url: base.resolve('/range')), '${temp.path}/r');
      expect(await file.readAsString(), 'part');
    });

    test('a failure deletes the partial file and keeps the target untouched', () async {
      final target = '${temp.path}/file.bin';
      await expectLater(
        http.download(LiveRequest(site: 'update', url: base.resolve('/forbidden')), target),
        throwsA(isA<HttpStatusFailure>().having((f) => f.status, 'status', 403)),
      );
      expect(File('$target.part').existsSync(), isFalse);
      expect(File(target).existsSync(), isFalse);
    });
  });
}
