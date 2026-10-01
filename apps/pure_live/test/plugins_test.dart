import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/backup/tv_sync.dart';
import 'package:pure_live/pages/settings/data_tools.dart';
import 'package:pure_live/shared/images.dart';
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
    currentStrings = (await tester.runAsync(loadStrings))!;
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
