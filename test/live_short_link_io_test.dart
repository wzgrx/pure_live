import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';

void main() {
  late io.HttpServer server;
  final paths = <String>[];

  setUp(() async {
    paths.clear();
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() => server.close(force: true));

  Dio createClient() {
    final client = Dio()
      ..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => io.HttpClient()..findProxy = (_) => 'DIRECT');
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final logical = options.uri;
          options.path = logical.replace(scheme: 'http', host: '127.0.0.1', port: server.port).toString();
          handler.next(options);
        },
      ),
    );
    return client;
  }

  test('real IO redirects resolve relative Location without fetching final room', () async {
    server.listen((request) async {
      paths.add(request.uri.path);
      request.response.statusCode = request.uri.path == '/first' ? 307 : 308;
      request.response.headers.set(
        'location',
        request.uri.path == '/first' ? '/second' : 'https://live.bilibili.com/123',
      );
      await request.response.close();
    });
    expect(await LiveUrlTool.parseLiveUrl('https://b23.tv/first', clientFactory: createClient), ['123', 'bilibili']);
    expect(paths, ['/first', '/second']);
  });

  test('real IO with stalled response headers completes at its deadline', () async {
    server.listen((request) {
      paths.add(request.uri.path);
    });
    expect(
      await LiveUrlTool.parseLiveUrl(
        'https://b23.tv/stall',
        clientFactory: createClient,
        timeout: const Duration(milliseconds: 200),
      ),
      isEmpty,
    );
    expect(paths, ['/stall']);
  });

  test('real IO JSON maps the internal ID and sends encoded query parameters', () async {
    final queries = <Map<String, String>>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      queries.add(request.uri.queryParameters);
      if (request.uri.path == '/first') {
        request.response.statusCode = 302;
        request.response.headers.set('location', 'https://webcast.amemv.com/reflow/123');
      } else {
        request.response.headers.contentType = io.ContentType.json;
        request.response.write('{"data":{"room":{"owner":{"web_rid":456}}}}');
      }
      await request.response.close();
    });
    expect(await LiveUrlTool.parseLiveUrl('https://v.douyin.com/first', clientFactory: createClient), [
      '456',
      'douyin',
    ]);
    expect(paths, ['/first', '/webcast/room/reflow/info/']);
    expect(queries.last['room_id'], '123');
    expect(queries.last['app_id'], '1128');
  });
}
