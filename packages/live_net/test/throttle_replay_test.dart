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

  test('replay matches JSON bodies structurally, ignoring listed keys at any depth', () async {
    final root = await Directory.systemTemp.createTemp('replay-json');
    addTearDown(() => root.delete(recursive: true));
    for (final (name, gear) in [('S01-g1', 1), ('S01-g4', 4)]) {
      final sample = Directory('${root.path}/$name')..createSync();
      File('${sample.path}/body.json').writeAsStringSync('{"gear":$gear}');
      File('${sample.path}/meta.json').writeAsStringSync(
        jsonEncode({
          'request': {
            'method': 'POST',
            'url': 'https://api.example.test/streams?seq=1',
            'body': jsonEncode({
              'head': {'seq': 1, 'cid': '9'},
              'avp': {'gear': gear, 'send_time': 1},
            }),
          },
          'response': {'status': 200, 'headers': <String, Object>{}},
          'body': 'body.json',
        }),
      );
    }
    final http = ReplayHttp.fixtures(root.path, ['S01-g1', 'S01-g4'], ignoredQuery: {'seq', 'send_time'});
    LiveRequest post(int gear, int time) => LiveRequest(
      site: 'x',
      url: Uri.parse('https://api.example.test/streams?seq=$time'),
      method: 'POST',
      body: utf8.encode(
        jsonEncode({
          'avp': {'send_time': time, 'gear': gear},
          'head': {'cid': '9', 'seq': time},
        }),
      ),
    );
    expect((await http.send(post(4, 77))).text, '{"gear":4}');
    expect((await http.send(post(1, 78))).text, '{"gear":1}');
    await expectLater(http.send(post(2, 79)), throwsA(isA<StateError>()));
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
