import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/pages/settings/data_tools.dart';
import 'package:pure_live/shared/images.dart';

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
}
