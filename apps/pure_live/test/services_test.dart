import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/downloads.dart';
import 'package:pure_live/app/fonts.dart';
import 'package:pure_live/features/remote_receiver/mdns_peers.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_service.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/routes/app_navigator.dart';

import 'support.dart';

/// Serves [files] by URL; honours `Range`; [failAfter] cuts the first answer
/// of a URL after that many bytes (a dropped connection).
final class FileServerHttp implements LiveHttp {
  new(this.files, {this.failAfter, this.refuse = const {}});

  final Map<String, List<int>> files;
  final int? failAfter;
  final Set<String> refuse;
  final List<LiveRequest> requests = [];
  final Set<String> _cut = {};

  @override
  Future<LiveResponse> send(LiveRequest request) async => await (await open(request)).collect();

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    requests.add(request);
    final url = request.url.toString();
    final bytes = files[url];
    if (bytes == null || refuse.contains(url)) {
      return LiveStreamedResponse(status: 404, body: const Stream.empty(), url: request.url);
    }
    final range = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(request.headers['range'] ?? '');
    var start = 0;
    var end = bytes.length - 1;
    if (range != null) {
      start = int.parse(range.group(1)!);
      if (range.group(2)!.isNotEmpty) end = int.parse(range.group(2)!);
      if (start >= bytes.length) {
        return LiveStreamedResponse(status: 416, body: const Stream.empty(), url: request.url);
      }
    }
    final part = bytes.sublist(start, end + 1);
    final cut = failAfter != null && range == null && _cut.add(url);
    Stream<List<int>> body() async* {
      if (cut) {
        yield part.sublist(0, failAfter);
        throw TransportFailure(request.site, TransportReason.protocol, 'dropped');
      }
      for (var i = 0; i < part.length; i += 1000) {
        yield part.sublist(i, i + 1000 > part.length ? part.length : i + 1000);
      }
    }

    return LiveStreamedResponse(
      status: range == null ? 200 : 206,
      body: body(),
      url: request.url,
      contentLength: part.length,
      headers: {
        if (range != null) 'content-range': ['bytes $start-$end/${bytes.length}'],
      },
    );
  }

  @override
  void close() {}
}

/// A TrueType-looking file of [size] bytes.
List<int> fakeFont(int size, [int fill = 7]) => [0, 1, 0, 0, for (var i = 4; i < size; i++) fill];

final class FakePeers implements MdnsPeers {
  void Function(MdnsPeer peer)? found;
  void Function(String id)? lost;
  Map<String, String>? attributes;
  bool stopped = false;

  @override
  Future<void> start({
    required String name,
    required int port,
    required Map<String, String> attributes,
    required void Function(MdnsPeer peer) found,
    required void Function(String id) lost,
  }) async {
    this.attributes = attributes;
    this.found = found;
    this.lost = lost;
  }

  @override
  Future<void> stop() async => stopped = true;
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('m12_4_'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('log', () {
    test('redacts cookies, tokens, passwords and signatures', () {
      const line =
          'Cookie: SESSDATA=abc123; bili_jct=xyz\n'
          'GET https://api.live.bilibili.com/x?room_id=1&w_rid=deadbeef&wts=17000 failed\n'
          '{"access_token":"t0k3n","nick":"主播","password":"hunter2"}\n'
          'Authorization: Bearer abc.def\n'
          'set acf_auth=AUTH; dy_auth=DY and https://user:pw@nas.local/dav\n'
          'udb_biztoken=XYZ; uid=42';
      final redacted = redactSecrets(line);
      for (final secret in ['abc123', 'xyz', 'deadbeef', '17000', 't0k3n', 'hunter2', 'abc.def', 'AUTH', 'DY', 'pw@']) {
        expect(redacted, isNot(contains(secret)), reason: secret);
      }
      expect(redacted, contains('room_id=1'));
      expect(redacted, contains('"nick":"主播"'));
      expect(redacted, contains('uid=42'));
      expect(redacted, contains('nas.local/dav'));
      expect(redactSecrets('the design was signed off'), 'the design was signed off');
    });

    test('keeps entries from the chosen level, writes a file while on, exports and clears', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final log = AppLog(capacity: 3);
      await log.attach(store.settings, directory: Directory(p.join(temp.path, 'logs')));
      log
        ..debug('t', 'hidden')
        ..info('t', 'one')
        ..warning('http', 'GET https://x/y?token=SECRET failed');
      expect([for (final e in log.entries) e.message], ['one', 'GET https://x/y?token=*** failed']);

      await store.settings.set(Settings.logLevel, 'debug');
      await pumpEventQueue();
      log
        ..debug('t', 'two')
        ..error('t', 'three', StateError('bad'));
      expect(log.entries.length, 3, reason: 'capacity');
      expect(log.writing, isFalse);

      await store.settings.set(Settings.enableLocalLog, true);
      await pumpEventQueue();
      expect(log.writing, isTrue);
      log.info('t', 'Cookie: SESSDATA=zzz');
      await log.flush();
      final written = log.file!.readAsStringSync();
      expect(written, contains('[ERROR] t: three'));
      expect(written, contains('Cookie: ***'));
      expect(written, isNot(contains('zzz')));

      final exported = await log.export(temp);
      expect(exported.readAsStringSync(), contains('[INFO] t: Cookie: ***'));

      await log.clear();
      expect(log.entries, isEmpty);
      await store.settings.set(Settings.enableLocalLog, false);
      await pumpEventQueue();
      expect(log.writing, isFalse);
      await log.close();
    });
  });

  group('downloads', () {
    test('resumes after a dropped connection and on the next source', () async {
      final bytes = List.generate(5000, (i) => i % 251);
      final http = FileServerHttp({'https://a/pkg.apk': bytes, 'https://b/pkg.apk': bytes}, failAfter: 1200);
      final target = File(p.join(temp.path, 'pkg.apk'));
      final progress = <int>[];
      final file = await FileDownloader(http).download(
        [Uri.parse('https://a/pkg.apk'), Uri.parse('https://b/pkg.apk')],
        target,
        onProgress: (received, total) => progress.add(received),
      );
      expect(file.readAsBytesSync(), bytes);
      expect(FileDownloader.partOf(target).existsSync(), isFalse);
      // a: cut at 1200; b: continues with a range from 1200.
      expect(http.requests.map((r) => r.headers['range']), [null, 'bytes=1200-']);
      expect(progress.last, 5000);
    });

    test('a cancel keeps the part and the next download continues it', () async {
      final bytes = List.generate(4000, (i) => i % 7);
      final http = FileServerHttp({'https://a/x.zip': bytes});
      final target = File(p.join(temp.path, 'x.zip'));
      FileDownloader.partOf(target).writeAsBytesSync(bytes.sublist(0, 1500));
      final cancel = CancelToken()..cancel();
      await expectLater(
        FileDownloader(http).download([Uri.parse('https://a/x.zip')], target, cancel: cancel),
        throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
      );
      expect(FileDownloader.partOf(target).lengthSync(), 1500);
      await FileDownloader(http).download([Uri.parse('https://a/x.zip')], target);
      expect(target.readAsBytesSync(), bytes);
      expect(http.requests.last.headers['range'], 'bytes=1500-');
    });

    test('every source failing is a network failure; folder and names', () async {
      final http = FileServerHttp({});
      await expectLater(
        FileDownloader(http).download([Uri.parse('https://a/none')], File(p.join(temp.path, 'none'))),
        throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.network)),
      );
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      expect((await resolveDownloadDirectory(store.settings, dataRoot: temp)).path, p.join(temp.path, 'downloads'));
      await store.settings.set(Settings.downloadDirectoryPath, '/mnt/pkgs');
      expect((await resolveDownloadDirectory(store.settings, dataRoot: temp)).path, '/mnt/pkgs');
      expect(safeDownloadFileName('https://x/a/PureLive%201.apk?x=1'), 'PureLive 1.apk');
      expect(safeDownloadFileName('https://x/', suggested: 'a:b?.exe'), 'a_b_.exe');
      expect(await canWriteDirectory(Directory(p.join(temp.path, 'new'))), isTrue);
    });
  });

  group('fonts', () {
    test("the bundled list is 3.x's and every entry is safe", () {
      final families = parseFontManifest(File(fontManifestAsset).readAsStringSync());
      expect(families.length, 57);
      expect(families.first.id, 'pingfang');
      expect(families.first.license, isNotEmpty);
      expect(
        parseFontManifest(
          jsonEncode([
            {
              'id': '../x',
              'name': 'bad',
              'files': ['x/a.ttf'],
            },
            {
              'id': 'ok',
              'name': 'bad file',
              'files': ['../a.ttf'],
            },
            {
              'id': 'ok',
              'name': 'not a font',
              'files': ['ok/a.txt'],
            },
          ]),
        ),
        isEmpty,
      );
    });

    test('downloads, registers, locks a weight, adopts 3.x files and deletes', () async {
      const manifest = [
        {
          'id': 'demo',
          'name': 'Demo',
          'files': ['demo/Demo-Regular.ttf', 'demo/Demo-Bold.ttf'],
          'license': {'name': 'OFL'},
        },
        {
          'id': 'old',
          'name': 'Old',
          'files': ['old/Old.ttf'],
        },
      ];
      final raw = fontRepository.raw('demo/Demo-Regular.ttf').toString();
      final bold = fontRepository.raw('demo/Demo-Bold.ttf').toString();
      final http = FileServerHttp({raw: fakeFont(3000), bold: fakeFont(2000, 9)});
      final legacy = Directory(p.join(temp.path, '3x', 'DOWNLOADS', 'fonts'));
      Directory(p.join(legacy.path, 'old')).createSync(recursive: true);
      File(p.join(legacy.path, 'old', 'Old.ttf')).writeAsBytesSync(fakeFont(500));
      final registered = <String, int>{};
      final library = FontLibrary(
        root: Directory(p.join(temp.path, 'fonts')),
        http: http,
        legacyRoots: legacyFontRoots([p.join(temp.path, '3x', 'HIVE_DB', 'app_settings.hive')]),
        manifest: () async => jsonEncode(manifest),
        register: (family, fonts) async => registered[family] = (await Future.wait(fonts)).length,
      );
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final settings = store.settings;

      final demo = (await library.family('demo'))!;
      final steps = <int>[];
      await library.download(demo, onProgress: (done, total) => steps.add(done));
      expect(steps, [0, 1, 2]);
      expect(library.isDownloaded('demo'), isTrue);
      expect(library.sizeOf('demo'), 5000);
      expect(Directory(library.root.path).listSync().map((e) => p.basename(e.path)), ['demo']);

      // A chosen weight registers that file only; restore at start.
      await settings.set(Settings.fontFamilyName, 'demo');
      await settings.set(Settings.fontFamilyFileName, 'Demo-Bold.ttf');
      // 3.x chose a danmaku font that is only in its own folder.
      await settings.set(Settings.danmakuFontFamilyName, 'old');
      await library.restore(settings);
      expect(registered, {'demo': 1, 'old': 1});
      expect(library.registered, {'demo', 'old'});
      expect(File(p.join(library.root.path, 'old', 'Old.ttf')).existsSync(), isTrue);
      expect(File(p.join(legacy.path, 'old', 'Old.ttf')).existsSync(), isTrue, reason: '3.x files are only read');

      // A missing weight falls back to the family and forgets the weight.
      final second = FontLibrary(root: library.root, http: http, register: (family, fonts) async {});
      await settings.set(Settings.fontFamilyFileName, 'Gone.ttf');
      await second.restore(settings);
      expect(second.registered, contains('demo'));
      expect(settings.get(Settings.fontFamilyFileName), '');

      expect(await library.delete('demo', settings), isTrue);
      expect(library.isDownloaded('demo'), isFalse);
      expect(settings.get(Settings.fontFamilyName), 'Default');
      expect(settings.get(Settings.danmakuFontFamilyName), 'old');
    });
  });

  group('platform', () {
    test('display mode info from the channel', () {
      final info = DisplayModeInfo.fromMap(const {
        'currentRefreshRate': 60.0,
        'maxRefreshRate': 120.0,
        'supportedRefreshRates': [60.0, 90.0, 120.0],
        'width': 1440,
        'height': 3200,
      });
      expect(info.rateLabel, '60 / 120 Hz');
      expect(info.supportedLabel, '60, 90, 120 Hz');
      DisplayMode.publish(info);
      expect(DisplayMode.info.value, info);
    });

    test('a LAN proxy asks for local-network access once', () async {
      final calls = <String>[];
      var granted = false;
      SystemAccess.debugCall = (method) async {
        calls.add(method);
        return method == 'localNetworkGranted' && granted;
      };
      addTearDown(() => SystemAccess.debugCall = null);
      final toasts = <String>[];
      final previous = AppNavigator.toast;
      AppNavigator.toast = toasts.add;
      addTearDown(() => AppNavigator.toast = previous);
      await loadStrings();
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final guard = LocalNetworkGuard(store.settings);
      expect(await guard.ensure(), isTrue);
      expect(calls, isEmpty, reason: 'no proxy');
      await store.settings.setAll({Settings.enableAppProxy: true, Settings.appProxyHost: '192.168.1.5'});
      expect(guard.needed, isTrue);
      expect(await guard.ensure(), isFalse);
      expect(await guard.ensure(), isFalse);
      expect(calls, ['localNetworkGranted', 'requestLocalNetwork', 'localNetworkGranted']);
      expect(toasts.single, contains('本地网络'));
      granted = true;
      expect(await guard.ensure(), isTrue);
      await store.settings.set(Settings.appProxyHost, 'proxy.example.com');
      expect(guard.needed, isFalse);
    });
  });

  test('device sync finds 3.x devices over mDNS with their TXT record', () async {
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);
    final peers = FakePeers();
    final service = RemoteSyncService(store, localIps: () => ['192.168.1.20'], mdns: peers);
    await service.start();
    expect(service.running, isTrue);
    expect(peers.attributes, {
      'id': service.deviceId,
      'name': RemoteSyncService.deviceName,
      'platform': Platform.operatingSystem,
      'version': peers.attributes!['version'],
      'ip': '192.168.1.20',
    });
    peers.found!((
      id: 'android-1',
      name: 'PureLive Android',
      platform: 'android',
      version: '1.0.0',
      ip: '192.168.1.8',
      port: 0,
    ));
    peers.found!((id: service.deviceId, name: 'me', platform: '', version: '', ip: '192.168.1.20', port: 39888));
    final device = service.devices.single;
    expect(device.address, '192.168.1.8:39888');
    expect(device.viaMdns, isTrue);
    peers.lost!('android-1');
    expect(service.devices, isEmpty);
    await service.stop();
    expect(peers.stopped, isTrue);
    service.dispose();
  });

  test('the fonts manifest and the WebDAV screenshots are assets', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/fonts/fonts-manifest.json'));
    expect(pubspec, contains('- assets/webdav/'));
    expect(Directory('assets/webdav').listSync().where((e) => e.path.endsWith('.png')).length, 7);
  });
}
