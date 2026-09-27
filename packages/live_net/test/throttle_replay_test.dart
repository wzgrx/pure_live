import 'dart:convert';
import 'dart:io';

import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

final class _Recorder implements LiveHttp {
  final List<String> sent = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    sent.add(request.url.path);
    return LiveResponse(status: 200, bytes: const [], url: request.url);
  }

  @override
  void close() {}
}

void main() {
  test('throttle spaces request starts per platform and leaves others alone', () async {
    var clock = DateTime.utc(2026, 9, 27, 12);
    final waits = <Duration>[];
    final inner = _Recorder();
    final http = ThrottledHttp(
      inner,
      minIntervals: const {'kuaishou': Duration(seconds: 5)},
      now: () => clock,
      sleep: (duration) async {
        waits.add(duration);
        clock = clock.add(duration);
      },
    );
    LiveRequest request(String site, String path) => LiveRequest(site: site, url: Uri.parse('https://x.test/$path'));
    await Future.wait([
      http.send(request('kuaishou', 'a')),
      http.send(request('kuaishou', 'b')),
      http.send(request('douyu', 'c')),
    ]);
    clock = clock.add(const Duration(seconds: 2));
    await http.send(request('kuaishou', 'd'));
    expect(inner.sent.toSet(), {'/a', '/b', '/c', '/d'});
    expect(waits, [const Duration(seconds: 5), const Duration(seconds: 3)]);
  });

  test('replay matches method, host, path and non-ignored query parameters', () async {
    final root = await Directory.systemTemp.createTemp('replay');
    addTearDown(() => root.delete(recursive: true));
    final sample = Directory('${root.path}/S01-a')..createSync();
    File('${sample.path}/body.json').writeAsStringSync('{"ok":1}');
    File('${sample.path}/meta.json').writeAsStringSync(
      jsonEncode({
        'request': {'method': 'GET', 'url': 'https://api.example.test/list?page=2&sign=SCRUBBED'},
        'response': {
          'status': 200,
          'headers': {
            'content-type': 'application/json',
            'set-cookie': ['a=1', 'b=2'],
          },
        },
        'body': 'body.json',
      }),
    );
    final http = ReplayHttp.fixtures(root.path, ['S01-a'], ignoredQuery: {'sign'});
    final response = await http.send(
      LiveRequest(site: 'x', url: Uri.parse('https://api.example.test/list?sign=fresh&page=2')),
    );
    expect(response.text, '{"ok":1}');
    expect(response.headers['set-cookie'], ['a=1', 'b=2']);
    expect(http.requests, hasLength(1));
    await expectLater(
      http.send(LiveRequest(site: 'x', url: Uri.parse('https://api.example.test/list?page=3'))),
      throwsA(isA<StateError>()),
    );
  });

  test('the cookie vault notifies changes only', () async {
    final vault = MemoryCookieVault();
    final changes = <String>[];
    final subscription = vault.changes.listen(changes.add);
    vault
      ..set('douyu', 'dy_did=1')
      ..set('douyu', 'dy_did=1')
      ..set('douyu', null)
      ..set('huya', null);
    await Future<void>.delayed(Duration.zero);
    expect(changes, ['douyu', 'douyu']);
    expect(vault.cookieFor('douyu'), isNull);
    await subscription.cancel();
    await vault.dispose();
  });
}
