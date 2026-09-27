import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/share/clipboard_watch.dart';
import 'package:pure_live_app/features/share/share_room.dart';
import 'package:pure_live_app/features/share/share_text.dart';

const _supported = {'bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'};

ShareTextRecognizer _recognizer({List<String>? asked}) => ShareTextRecognizer(
  supports: _supported.contains,
  resolveLink: (text) async {
    asked?.add(text);
    final match = RegExp(r'douyu\.com/(\d+)').firstMatch(text);
    return match == null ? null : RoomRef('douyu', match[1]!);
  },
);

void main() {
  final code = ShareCode(RoomRef('huya', '660000'), title: '晚间直播', anchorName: '主播A').encode();

  group('recognizer', () {
    test('finds a share code, alone or inside other text', () async {
      final recognizer = _recognizer();
      final alone = await recognizer.recognize('  $code\n');
      expect(alone, SharedRoom(RoomRef('huya', '660000'), title: '晚间直播', anchorName: '主播A', fromShareCode: true));
      final inText = await recognizer.recognize('【纯粹直播】复制这段口令打开 $code 快来看');
      expect(inText?.ref, RoomRef('huya', '660000'));
    });

    test('finds a room link through the adapters, without asking them about plain text', () async {
      final asked = <String>[];
      final recognizer = _recognizer(asked: asked);
      expect((await recognizer.recognize('https://www.douyu.com/5526219'))?.ref, RoomRef('douyu', '5526219'));
      expect(await recognizer.recognize('今天吃什么'), isNull);
      expect(await recognizer.recognize('https://example.com/news'), isNull);
      expect(asked, ['https://www.douyu.com/5526219', 'https://example.com/news']);
    });

    test('ignores platforms this build has no adapter for and broken codes', () async {
      final recognizer = _recognizer();
      final twitch = ShareCode(RoomRef('twitch', 'someone')).encode();
      expect(await recognizer.recognize(twitch), isNull);
      expect(await recognizer.recognize(code.substring(0, code.length - 6)), isNull);
      expect(await recognizer.recognize('x' * (ShareTextRecognizer.maxLength + 1)), isNull);
    });

    test('an adapter error is not a match', () async {
      final recognizer = ShareTextRecognizer(supports: (_) => true, resolveLink: (_) => throw StateError('offline'));
      expect(await recognizer.recognize('https://www.douyu.com/1'), isNull);
    });
  });

  group('clipboard watcher', () {
    late String? clipboard;
    late bool enabled;
    late List<SharedRoom> offered;
    late int reads;
    late ClipboardShareWatcher watcher;

    setUp(() {
      clipboard = null;
      enabled = true;
      offered = [];
      reads = 0;
      watcher = ClipboardShareWatcher(
        read: () async {
          reads++;
          return clipboard;
        },
        recognizer: _recognizer(),
        present: (room) async => offered.add(room),
        enabled: () => enabled,
      );
    });

    test('offers a copied share code once', () async {
      clipboard = code;
      expect(await watcher.check(), isTrue);
      expect(offered.single.ref, RoomRef('huya', '660000'));
      expect(await watcher.check(), isFalse, reason: 'the same clipboard content is not offered again');
      clipboard = 'https://www.douyu.com/5526219';
      expect(await watcher.check(), isTrue);
      expect(offered.last.ref, RoomRef('douyu', '5526219'));
      expect(offered.last.fromShareCode, isFalse);
    });

    test('does not read the clipboard when turned off', () async {
      clipboard = code;
      enabled = false;
      expect(await watcher.check(), isFalse);
      expect(reads, 0);
      enabled = true;
      expect(await watcher.check(), isTrue);
    });

    test('never offers the share code the app copied itself', () async {
      watcher.remember(code);
      clipboard = code;
      expect(await watcher.check(), isFalse);
      expect(offered, isEmpty);
    });

    test('concurrent checks share one read and one dialog', () async {
      final dialog = Completer<void>();
      final slow = ClipboardShareWatcher(
        read: () async {
          reads++;
          return code;
        },
        recognizer: _recognizer(),
        present: (room) {
          offered.add(room);
          return dialog.future;
        },
        enabled: () => true,
      );
      final first = slow.check();
      final second = slow.check();
      dialog.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(reads, 1);
      expect(offered, hasLength(1));
    });

    test('an unreadable clipboard is ignored', () async {
      final broken = ClipboardShareWatcher(
        read: () => throw StateError('no clipboard'),
        recognizer: _recognizer(),
        present: (room) async => offered.add(room),
        enabled: () => true,
      );
      expect(await broken.check(), isFalse);
    });
  });

  test('the room share code is 3.x compatible and carries the display data', () {
    final detail = RoomDetail(
      card: RoomCard(
        ref: RoomRef('douyu', '5526219'),
        title: '标题',
        anchorName: '主播',
        state: LiveState.live,
        cover: Uri.parse('https://example.com/c.jpg'),
      ),
      link: Uri.parse('https://www.douyu.com/5526219'),
      avatar: Uri.parse('https://example.com/a.jpg'),
    );
    final decoded = ShareCode.decode(shareCodeOf(detail))!;
    expect(decoded.ref, RoomRef('douyu', '5526219'));
    expect(decoded.title, '标题');
    expect(decoded.anchorName, '主播');
    expect(decoded.link, 'https://www.douyu.com/5526219');
    expect(decoded.cover, 'https://example.com/c.jpg');
    expect(decoded.avatar, 'https://example.com/a.jpg');
    expect(ShareTextRecognizer.findShareCode(shareCodeOf(detail))?.ref, RoomRef('douyu', '5526219'));
  });
}
