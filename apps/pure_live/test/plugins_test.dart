import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/desktop/startup_entry.dart';
import 'package:pure_live/app/desktop/title_bar.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/features/account/bilibili_web_login.dart';
import 'package:pure_live/features/backup/tv_sync.dart';
import 'package:pure_live/features/settings/data_tools.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/images.dart';
import 'package:pure_live/shared/in_app_web.dart';
import 'package:pure_live/shared/qr_scan.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearing the image cache empties the disk through the cache manager and renews the keys', () async {
    final previous = ImageCacheTools.clearDisk;
    addTearDown(() => ImageCacheTools.clearDisk = previous);
    var emptied = 0;
    ImageCacheTools.clearDisk = () async => emptied++;
    final epoch = imageCacheEpoch.value;

    await ImageCacheTools.clear();
    expect(emptied, 1);
    expect(imageCacheEpoch.value, epoch + 1, reason: 'covers on screen load again');

    await ImageCacheTools.refreshInBackground();
    expect(emptied, 2);
    expect(imageCacheEpoch.value, epoch + 1, reason: 'the timed refresh leaves the covers on screen');
  });

  testWidgets('covers are refreshed on the chosen interval while the setting is on', (tester) async {
    final store = (await tester.runAsync(() => LiveStore.memory(cipher: FakeCipher())))!;
    addTearDown(() => tester.runAsync(store.close));
    var runs = 0;
    final timer = CoverRefreshTimer(store.settings, refresh: () async => runs++)..start();
    addTearDown(timer.dispose);
    await tester.pump();
    expect(timer.active, isFalse, reason: 'off by default (3.x)');

    await tester.runAsync(() async {
      await store.settings.setAll({Settings.autoRefreshThumbnails: true, Settings.thumbnailRefreshInterval: 5});
    });
    await tester.pump();
    expect(timer.active, isTrue);
    await tester.pump(const Duration(minutes: 5));
    expect(runs, 1);
    await tester.pump(const Duration(minutes: 5));
    expect(runs, 2);

    await tester.runAsync(() => store.settings.set(Settings.autoRefreshThumbnails, false));
    await tester.pump();
    expect(timer.active, isFalse);
    await tester.pump(const Duration(minutes: 10));
    expect(runs, 2);
  });

  test('the network kind: offline, mobile data only, anything else', () {
    expect(networkKindOf(const []), NetworkKind.none);
    expect(networkKindOf(const [ConnectivityResult.none]), NetworkKind.none);
    expect(networkKindOf(const [ConnectivityResult.mobile]), NetworkKind.mobile);
    expect(networkKindOf(const [ConnectivityResult.mobile, ConnectivityResult.wifi]), NetworkKind.other);
    expect(networkKindOf(const [ConnectivityResult.ethernet]), NetworkKind.other);
    expect(networkKindOf(const [ConnectivityResult.vpn]), NetworkKind.other);
  });

  test('a list refresh checks the network first: offline asks nothing, mobile data shows the notice', () async {
    currentStrings = await loadStrings();
    var asked = 0;
    var kind = NetworkKind.none;
    final feed = RoomFeed(
      platform: 'fake',
      source: _OnePage(() => asked++),
      visible: (_) => true,
      precheck: () => MobileDataNotice.precheck(() async => kind),
    );
    addTearDown(feed.dispose);
    MobileDataNotice.onMobileData.value = false;

    await feed.refresh(count: 1);
    expect(asked, 0);
    expect(feed.error, isA<Offline>());
    expect(describeLoadError(feed.error), '当前无网络连接，请检查网络设置');

    kind = NetworkKind.mobile;
    await feed.refresh(count: 1);
    expect(asked, 1);
    expect(feed.rooms, hasLength(1));
    expect(MobileDataNotice.onMobileData.value, isTrue);

    kind = NetworkKind.other;
    await feed.refresh(count: 1);
    expect(MobileDataNotice.onMobileData.value, isFalse);
  });

  testWidgets("the TV dialog reads the TV's QR code when there is a scanner (mobile_scanner)", (tester) async {
    currentStrings = await tester.runAsync(loadStrings);
    addTearDown(() => QrScan.scan = null);
    String? origin;
    Future<void> pump() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) =>
                TextButton(onPressed: () async => origin = await askTvAddress(context), child: const Text('open')),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    QrScan.scan = null;
    await pump();
    expect(find.byKey(const ValueKey('backup-tv-scan')), findsNothing, reason: 'no scanner on desktops');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    QrScan.scan = (_) async => 'http://192.168.1.5:8080/';
    await pump();
    await tester.tap(find.byKey(const ValueKey('backup-tv-scan')));
    await tester.pumpAndSettle();
    expect(origin, contains('192.168.1.5:8080'));
  });

  test('Windows: the remembered place and the start-up entry', () {
    expect(parseWindowPosition(formatWindowPosition(const Offset(-1919.6, 40.2))), const Offset(-1920, 40));
    expect(parseWindowPosition(null), isNull);
    expect(parseWindowPosition('12'), isNull);
    expect(parseWindowPosition('a,b'), isNull);

    const exe = r'C:\Apps\PureLive v4\pure_live.exe';
    expect(startupValueName, isNot('PureLive'), reason: "3.x's entry is never touched");
    expect(commandTargets(startupCommand(exe), exe), isTrue);
    expect(
      commandTargets('"c:/apps/purelive v4/PURE_LIVE.exe" --hidden', exe.replaceAll('PureLive v4', 'purelive v4')),
      isTrue,
    );
    expect(commandTargets(r'"D:\Soft\PureLive\pure_live.exe"', exe), isFalse);
    expect(commandTargets(null, exe), isFalse);
  });

  testWidgets('Windows: the title bar sits above the app and hides in full screen', (tester) async {
    currentStrings = await tester.runAsync(loadStrings);
    var closes = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => DesktopFrame(enabled: true, child: child!),
        home: const Scaffold(body: Text('page')),
      ),
    );
    expect(find.byType(DesktopTitleBar), findsOneWidget);
    expect(find.text('纯粹直播'), findsOneWidget);
    expect(find.text('page'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Column(
          children: [
            DesktopTitleBar(onClose: () async => closes++),
            Expanded(child: child!),
          ],
        ),
        home: const Scaffold(body: Text('page')),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('title-bar-close')));
    await tester.pump();
    expect(closes, 1, reason: 'close follows the close setting through the shell');

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => DesktopFrame(enabled: true, child: child!),
        home: const Scaffold(body: Text('page')),
      ),
    );
    await DesktopWindow.setFullScreen(on: true);
    await tester.pump();
    expect(find.byType(DesktopTitleBar), findsNothing);
    await DesktopWindow.setFullScreen(on: false);
    await tester.pump();
    expect(find.byType(DesktopTitleBar), findsOneWidget);
  });

  test('in-app web: web pages only; the Bilibili login lands on the main site with its cookies', () {
    expect(InAppWeb.available, isFalse, reason: 'tests and Linux use the system browser');
    expect(isWebPage(Uri.parse('https://www.huya.com/search?hsk=a')), isTrue);
    expect(isWebPage(Uri.parse('bilibili://live/1')), isFalse);
    expect(isWebPage(Uri.parse('javascript:alert(1)')), isFalse);
    expect(isBilibiliHome(Uri.parse('https://www.bilibili.com/')), isTrue);
    expect(isBilibiliHome(Uri.parse('https://m.bilibili.com/index.html')), isTrue);
    expect(isBilibiliHome(bilibiliPassportLogin), isFalse);
    expect(
      cookieHeader([(name: 'SESSDATA', value: 'a'), (name: 'bili_jct', value: 'b'), (name: 'SESSDATA', value: 'c')]),
      'SESSDATA=a; bili_jct=b',
    );
  });
}

/// One room in one chunk.
final class _OnePage implements RoomSource {
  new(this._asked);

  final void Function() _asked;

  @override
  Future<RoomChunk> next(CancelToken cancel) async {
    _asked();
    return RoomChunk([LiveRoom(platform: 'fake', roomId: '1')], hasMore: false);
  }

  @override
  RoomSource restart() => this;
}
