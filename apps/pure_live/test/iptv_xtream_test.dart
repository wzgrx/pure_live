import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/iptv/iptv_sync.dart';
import 'package:pure_live_app/features/iptv/xtream.dart';

/// An Xtream server: answers by path, checks the credentials.
final class _Xtream implements LiveHttp {
  String status = 'Active';
  int auth = 1;
  final requests = <Uri>[];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final url = request.url;
    requests.add(url);
    final ok = url.queryParameters['username'] == 'u' && url.queryParameters['password'] == 'p&w';
    final body = switch (url.path) {
      '/player_api.php' => jsonEncode({
        'user_info': {'auth': ok ? auth : 0, 'status': status, 'exp_date': '1893456000', 'max_connections': '2'},
      }),
      '/get.php' when ok =>
        '#EXTM3U url-tvg="${url.replace(path: '/xmltv.php')}"\n'
            '#EXTINF:-1 tvg-id="c1" group-title="新闻",新闻台\n'
            'http://tv.fixture:8080/live/u/p&w/1.ts\n',
      '/xmltv.php' when ok => '<tv><channel id="c1"><display-name>新闻台</display-name></channel></tv>',
      _ => null,
    };
    return LiveResponse(status: body == null ? 404 : 200, bytes: body == null ? const [] : utf8.encode(body), url: url);
  }

  @override
  void close() {}
}

void main() {
  test('F-IPTV-07: accounts parse from what the user types', () {
    final account = XtreamAccount.tryParse(server: ' tv.fixture:8080/anything?x=1 ', username: 'u', password: 'p&w')!;
    expect(account.server, Uri.parse('http://tv.fixture:8080'));
    expect(account.playlistUri.queryParameters, {
      'username': 'u',
      'password': 'p&w',
      'type': 'm3u_plus',
      'output': 'ts',
    });
    expect(account.guideUri.path, '/xmltv.php');
    expect(XtreamAccount.tryParse(server: 'ftp://x', username: 'u', password: 'p'), isNull);
    expect(XtreamAccount.tryParse(server: 'x', username: '', password: 'p'), isNull);
    expect(XtreamAccount.fromJson(account.toJson())!.password, 'p&w');
  });

  test('F-IPTV-07: player_api answers', () {
    expect(
      parseXtreamStatus({
        'user_info': {'auth': 1, 'status': 'Active'},
      }).usable,
      isTrue,
    );
    expect(
      parseXtreamStatus({
        'user_info': {'auth': '1', 'status': 'Expired'},
      }).problem,
      '账号已过期',
    );
    expect(
      parseXtreamStatus({
        'user_info': {'auth': 0},
      }).problem,
      '用户名或密码不对',
    );
    expect(parseXtreamStatus('nonsense').authorized, isFalse);
    expect(
      parseXtreamStatus({
        'user_info': {'auth': 1, 'exp_date': '1893456000'},
      }).expiresAt,
      DateTime.utc(2030),
    );
  });

  group('IptvSync.importXtream', () {
    late LiveStore store;
    late SecretStore secrets;
    late _Xtream http;
    late Directory directory;
    late IptvSync sync;

    setUp(() async {
      store = await LiveStore.inMemory();
      secrets = await SecretStore.memory();
      http = _Xtream();
      directory = await Directory.systemTemp.createTemp('xtream-test-');
      sync = IptvSync(
        store: store.iptv,
        fetcher: IptvFetcher(http),
        settings: store.settings,
        directory: () async => directory,
        xtream: XtreamVault(secrets),
        compute: <R>(R Function() task) async => task(),
      );
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    test('the password stays in the secret store; the line-up and the guide sync', () async {
      final account = XtreamAccount.tryParse(server: 'http://tv.fixture:8080', username: 'u', password: 'p&w')!;
      final result = await sync.importXtream(account);
      expect(result.channels, 1);
      final playlist = (await store.iptv.playlists()).single;
      expect(playlist.source, startsWith(xtreamScheme));
      expect(playlist.source, isNot(contains('p&w')));
      expect(playlist.guideUrl, isNull, reason: 'the file names its guide with the password');
      expect(playlist.name, 'Xtream tv.fixture');
      final guide = (await store.iptv.guideSources()).single;
      expect(guide.source, '${playlist.source}#guide');
      expect(guide.channelCount, 1);
      expect(XtreamVault(secrets).read(xtreamIdOf(playlist.source)!)!.password, 'p&w');

      // A sync downloads through the stored account again.
      await sync.syncPlaylist(playlist);
      expect(http.requests.where((url) => url.path == '/get.php'), hasLength(2));

      // Deleting it takes the guide and the account.
      await sync.deletePlaylist(playlist);
      expect(await store.iptv.guideSources(), isEmpty);
      expect(XtreamVault(secrets).read(xtreamIdOf(playlist.source)!), isNull);
    });

    test('a refused account adds nothing', () async {
      http.status = 'Expired';
      final account = XtreamAccount.tryParse(server: 'tv.fixture:8080', username: 'u', password: 'p&w')!;
      await expectLater(sync.importXtream(account), throwsA(isA<XtreamRejectedError>()));
      expect(await store.iptv.playlists(), isEmpty);
      final wrong = XtreamAccount.tryParse(server: 'tv.fixture:8080', username: 'u', password: 'bad')!;
      await expectLater(
        sync.importXtream(wrong),
        throwsA(isA<XtreamRejectedError>().having((error) => error.message, 'message', '用户名或密码不对')),
      );
    });
  });
}
