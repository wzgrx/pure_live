import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/shared/danmaku/masked_blocks.dart';

import '../support.dart';

// Task B01 c2 (audit B-1): blocked masked names are removed once, and the
// block manager is told once.

void main() {
  late LiveStore store;

  setUp(() async => store = await LiveStore.memory(cipher: FakeCipher()));
  tearDown(() => store.close());

  test('masked names: ** or ＊＊ of two or more, around spaces; full names are not', () {
    expect(isMaskedViewerName('观***'), isTrue);
    expect(isMaskedViewerName(' 离** '), isTrue);
    expect(isMaskedViewerName('ab＊＊'), isTrue);
    expect(isMaskedViewerName('路人'), isFalse);
    expect(isMaskedViewerName('a*b'), isFalse);
    expect(isMaskedViewerName(''), isFalse);
  });

  test('removes the masked blocked viewers once, keeping the rest and their order; the notice is owed once', () async {
    await store.blockLists.replaceAll(BlockKind.user, ['路人', '观***', 'Alice', '离**']);
    await store.blockLists.replaceAll(BlockKind.keyword, ['剧透', '***']);

    expect(await MaskedNameBlocks.cleanOnce(store.blockLists, store.meta), 2);
    expect(await store.blockLists.list(BlockKind.user), ['路人', 'Alice']);
    expect(await store.blockLists.list(BlockKind.keyword), ['剧透', '***'], reason: 'keywords are left alone');
    expect(await store.meta.get(MaskedNameBlocks.doneKey), '2');

    // A masked name blocked again later (a restored backup) stays: the
    // cleanup ran once; the block list ignores it anyway.
    await store.blockLists.add(BlockKind.user, '观***');
    expect(await MaskedNameBlocks.cleanOnce(store.blockLists, store.meta), 0);
    expect(await store.blockLists.list(BlockKind.user), ['路人', 'Alice', '观***']);

    expect(await MaskedNameBlocks.takeNotice(store.meta), 2);
    expect(await MaskedNameBlocks.takeNotice(store.meta), isNull, reason: 'said once');
  });

  test('nothing masked: nothing removed, no notice, and it does not run again', () async {
    await store.blockLists.replaceAll(BlockKind.user, ['路人']);
    expect(await MaskedNameBlocks.cleanOnce(store.blockLists, store.meta), 0);
    expect(await store.meta.get(MaskedNameBlocks.doneKey), '0');
    expect(await MaskedNameBlocks.takeNotice(store.meta), isNull);
    await store.blockLists.add(BlockKind.user, '观***');
    expect(await MaskedNameBlocks.cleanOnce(store.blockLists, store.meta), 0);
    expect(await store.blockLists.list(BlockKind.user), ['路人', '观***']);
  });
}
