import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/diagnostics/app_log.dart';
import 'package:pure_live_app/features/diagnostics/crash_handler.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_bundle.dart';
import 'package:pure_live_app/features/diagnostics/log_scrubber.dart';

void main() {
  group('LogScrubber', () {
    const cookie = 'SESSDATA=abc123%2C1700000000%2Cdef*56; bili_jct=0123456789abcdef; DedeUserID=42';

    test('removes cookie and authorization headers', () {
      final text = LogScrubber.scrub('request\nCookie: $cookie\nAuthorization: Basic dXNlcjpwYXNz\nnext line');
      expect(text, isNot(contains('abc123')));
      expect(text, isNot(contains('dXNlcjpwYXNz')));
      expect(text, contains('Cookie: <redacted>'));
      expect(text, contains('Authorization: <redacted>'));
      expect(text, contains('next line'));
    });

    test('removes secret-looking key=value and JSON pairs', () {
      final text = LogScrubber.scrub(
        'set $cookie and {"password": "hunter22", "token":"t0k3n", "passphrase": "open sesame"} acf_auth=zzz',
      );
      for (final secret in ['abc123', '0123456789abcdef', 'hunter22', 't0k3n', 'open', 'zzz']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(text, contains('"password": "<redacted>"'));
    });

    test('removes URL credentials and signed query strings', () {
      final text = LogScrubber.scrub(
        'GET https://user:secret@dav.example.com/dav/ then '
        'https://tx.flv.huya.com/src/1-2.flv?wsSecret=9f8e7d&wsTime=65f00000&fm=abc stop',
      );
      expect(text, isNot(contains('secret@')));
      expect(text, isNot(contains('9f8e7d')));
      expect(text, contains('https://<redacted>@dav.example.com/dav/'));
      expect(text, contains('https://tx.flv.huya.com/src/1-2.flv?<redacted>'));
      expect(text, endsWith(' stop'));
    });

    test('removes pairing codes and long opaque tokens but keeps ordinary text', () {
      final token = 'A' * 20 + 'b9_-' * 10;
      final text = LogScrubber.scrub('x-purelive-pairing: 123456\nopaque $token end');
      expect(text, isNot(contains('123456')));
      expect(text, isNot(contains(token)));
      const plain = 'lan: sent to 192.168.1.5:39888: applied; room douyu:5526219 at package:pure_live_app/main.dart:12';
      expect(LogScrubber.scrub(plain), plain);
    });
  });

  group('AppLog', () {
    late Directory directory;

    setUp(() => directory = Directory.systemTemp.createTempSync('pure_live_log_'));
    tearDown(() => directory.deleteSync(recursive: true));

    test('writes scrubbed lines and keeps the recent ones in memory', () async {
      final log = await AppLog.open(directory, clock: () => DateTime.utc(2026, 9, 27, 2));
      log
        ..info('app', 'start')
        ..warning('net', 'failed with Cookie: SESSDATA=abc')
        ..error('ui', 'boom', StateError('bad'), StackTrace.fromString('#0 main (file.dart:1)\n#1 run (file.dart:2)'));
      final lines = await log.readAll();
      expect(lines.first, '2026-09-27T02:00:00.000Z I app: start');
      expect(lines[1], contains('Cookie: <redacted>'));
      expect(lines.join('\n'), isNot(contains('SESSDATA=abc')));
      expect(lines[2], contains('E ui: boom | Bad state: bad'));
      expect(lines[3].trim(), '#0 main (file.dart:1)');
      expect(log.recent, lines);
    });

    test('rotates files and stays within its bound', () async {
      final log = await AppLog.open(directory, maxFileBytes: 1000);
      for (var i = 0; i < 200; i++) {
        log.info('loop', 'line $i ${'x' * 40}');
      }
      final files = directory.listSync().whereType<File>().map((file) => file.uri.pathSegments.last).toSet();
      expect(files, {'app.log', 'app.1.log', 'app.2.log'});
      final total = directory.listSync().whereType<File>().fold<int>(0, (sum, file) => sum + file.lengthSync());
      expect(total, lessThanOrEqualTo(3000));
      final lines = await log.readAll();
      expect(lines.last, contains('line 199'));
      // Oldest first across the rotated files.
      final numbers = [for (final line in lines) int.parse(RegExp(r'line (\d+)').firstMatch(line)![1]!)];
      expect(numbers, [for (var i = numbers.first; i <= 199; i++) i]);
    });

    test('an in-memory log keeps only the recent lines', () async {
      final log = AppLog.memory();
      for (var i = 0; i < AppLog.recentLimit + 10; i++) {
        log.info('t', '$i');
      }
      expect(log.recent, hasLength(AppLog.recentLimit));
      expect(log.recent.last, endsWith('t: ${AppLog.recentLimit + 9}'));
      expect(await log.readAll(), log.recent);
    });

    test('clear removes every file', () async {
      final log = await AppLog.open(directory, maxFileBytes: 100);
      for (var i = 0; i < 20; i++) {
        log.info('t', 'line $i');
      }
      await log.clear();
      expect(directory.listSync(), isEmpty);
      expect(await log.readAll(), isEmpty);
    });

    test('the crash marker is taken once', () async {
      final log = await AppLog.open(directory);
      final marker = CrashMarker(log);
      expect(marker.take(), isFalse);
      marker.mark();
      expect(marker.take(), isTrue);
      expect(marker.take(), isFalse);
      expect(CrashMarker(AppLog.memory()).take(), isFalse);
    });
  });

  test('the diagnostics bundle has settings, counts and the log, never secrets', () async {
    final store = await LiveStore.inMemory();
    addTearDown(store.close);
    final secrets = await SecretStore.memory({
      SecretRefs.cookie('bilibili'): 'SESSDATA=topsecretcookie; bili_jct=abc',
      SecretRefs.webdav('p1'): 'webdav-password-1',
    });
    await store.settings.set(Settings.danmakuSpeed, 150);
    await store.follows.follow(RoomSnapshot(ref: RoomRef('douyu', '5526219'), anchorName: '主播'));
    final log = AppLog.memory()
      ..info('app', 'start')
      ..warning('net', 'sent Cookie: ${secrets.cookieFor('bilibili')}');

    final bundle = await DiagnosticsBundle.build(store: store, log: log, now: DateTime.utc(2026, 9, 27));
    final text = jsonEncode(bundle);
    expect(bundle['format'], DiagnosticsBundle.format);
    expect((bundle['app']! as Map)['version'], isNotEmpty);
    expect((bundle['device']! as Map)['os'], Platform.operatingSystem);
    final settings = bundle['settings']! as Map<String, Object?>;
    expect(settings['danmaku.speed'], {'value': 150.0, 'changed': true});
    expect(settings['theme.mode'], {'value': 'system'});
    expect((bundle['data']! as Map)['follows'], 1);
    expect(bundle['log'], hasLength(2));
    expect(text, isNot(contains('topsecretcookie')));
    expect(text, isNot(contains('webdav-password-1')));
    expect(DiagnosticsBundle.fileName(DateTime(2026, 9, 27, 8, 5, 3)), 'PureLive-diagnostics-20260927-080503.json');
  });
}
