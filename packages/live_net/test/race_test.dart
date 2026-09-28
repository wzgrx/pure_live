import 'dart:async';
import 'dart:io';

import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

void main() {
  final a = Uri.parse('https://a.test/');
  final b = Uri.parse('https://b.test/');
  final c = Uri.parse('https://c.test/');

  test('the first non-null result wins and the other tasks are cancelled', () async {
    final tokens = <Uri, CancelToken>{};
    final result = await raceFirst<String>([a, b, c], (url, cancel) async {
      tokens[url] = cancel;
      if (url == a) return null;
      if (url == b) return 'b';
      await cancel.whenCancelled;
      return 'c too late';
    }, timeout: const Duration(seconds: 5));
    expect(result, 'b');
    expect(tokens.values.every((token) => token.isCancelled), isTrue);
  });

  test('when every task fails or gives null the race ends at once, not at the timeout', () async {
    final watch = Stopwatch()..start();
    final result = await raceFirst<String>([a, b], (url, cancel) async {
      if (url == a) throw StateError('mirror down');
      return null;
    }, timeout: const Duration(seconds: 30));
    expect(result, isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('the timeout ends a race nobody wins; no URLs give null', () async {
    final result = await raceFirst<String>(
      [a],
      (url, cancel) => cancel.whenCancelled.then((_) => 'late'),
      timeout: const Duration(milliseconds: 50),
    );
    expect(result, isNull);
    expect(await raceFirst<String>(const [], (_, _) async => 'x', timeout: const Duration(seconds: 1)), isNull);
  });

  group('over HTTP', () {
    late HttpServer server;
    late Uri base;
    late IoLiveHttp http;
    final ranges = <String?>[];

    setUp(() async {
      ranges.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://127.0.0.1:${server.port}');
      http = IoLiveHttp();
      server.listen((request) async {
        ranges.add(request.headers.value('range'));
        final response = request.response;
        switch (request.uri.path) {
          case '/manifest':
            response.write('{"version":"3.2.11"}');
          case '/array':
            response.write('[1]');
          case '/slow':
            await Future<void>.delayed(const Duration(seconds: 2));
            response.write('{"version":"slow"}');
          case '/partial':
            response
              ..statusCode = HttpStatus.partialContent
              ..write('x');
          default:
            response.statusCode = HttpStatus.notFound;
        }
        await response.close();
      });
    });

    tearDown(() async {
      http.close();
      await server.close(force: true);
    });

    test('raceJson returns the first JSON object with status 200', () async {
      final json = await raceJson(http, 'update', [
        base.resolve('/missing'),
        base.resolve('/array'),
        base.resolve('/slow'),
        base.resolve('/manifest'),
      ]);
      expect(json, {'version': '3.2.11'});
    });

    test('fastestUrl probes with a one-byte range and accepts 206', () async {
      final url = await fastestUrl(http, 'update', [base.resolve('/missing'), base.resolve('/partial')]);
      expect(url, base.resolve('/partial'));
      expect(ranges, everyElement('bytes=0-0'));
    });
  });

  test("GitHub mirrors: the raw URL, 3.x's proxy prefixes in order, kkgithub, jsDelivr and Fastly", () {
    final mirrors = const GitHubMirror(owner: 'o', repo: 'r').mirrors('assets/a.json');
    const raw = 'https://raw.githubusercontent.com/o/r/master/assets/a.json';
    expect(mirrors.map((url) => url.toString()), [
      raw,
      for (final prefix in GitHubMirror.rawPrefixes) '$prefix$raw',
      'https://raw.kkgithub.com/o/r/master/assets/a.json',
      'https://cdn.jsdelivr.net/gh/o/r@master/assets/a.json',
      'https://fastly.jsdelivr.net/gh/o/r@master/assets/a.json',
    ]);
    expect(mirrors, hasLength(18));
    expect(mirrors.toSet(), hasLength(mirrors.length));
    expect(GitHubMirror.rawPrefixes.first, 'https://cdn.gh-proxy.org/');
  });
}
