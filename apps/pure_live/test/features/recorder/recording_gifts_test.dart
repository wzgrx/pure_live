import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/shared/danmaku/gift_combo.dart' as app;
import 'package:pure_live/shared/danmaku/gift_words.dart';

import '../../support.dart';
import '../live_play/live_play_support.dart';

// H01.8 (docs/H-录制/H01-录制核心/H01.8-弹幕XML带礼物): the recording's chat
// connector hands the file the room's gifts and super chats only while
// "录制弹幕时包含礼物" is on, through the room's gift filter (D07.1).

LiveMessage _gift(String name, {String user = '观众', bool local = false, bool withGift = true}) => LiveMessage(
  type: LiveMessageType.gift,
  userName: user,
  userId: user,
  message: '$name ×1',
  color: LiveMessageColor.white,
  isLocal: local,
  data: withGift ? LiveGift(name: name, id: name) : null,
);

final _superChat = LiveMessage(
  type: LiveMessageType.superChat,
  userName: 'SUPER_CHAT_MESSAGE',
  message: 'SUPER_CHAT_MESSAGE',
  color: LiveMessageColor.white,
  data: LiveSuperChatMessage(
    messageId: 'sc-1',
    userName: '甲',
    face: '',
    message: '加油',
    price: 30,
    startTime: DateTime.utc(2026, 10, 9),
    endTime: DateTime.utc(2026, 10, 9, 0, 1),
    backgroundColor: '',
    backgroundBottomColor: '',
  ),
);

RecordTask _task() => RecordTask(
  taskId: 'bilibili_6',
  roomId: '6',
  platform: SiteIds.bilibili,
  title: 't',
  nick: '主播',
  avatar: '',
  cover: '',
  createTime: DateTime(2026, 10, 9),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStrings);

  late LiveStore store;
  late FakeDanmaku danmaku;
  late RecordChatConnector connect;
  setUp(() async {
    store = await LiveStore.memory(cipher: FakeCipher());
    danmaku = FakeDanmaku();
    connect = recordChatConnector(
      sites: SiteRegistry({SiteIds.bilibili: () => FakeSite(LiveRoom(platform: SiteIds.bilibili, roomId: '6'))}),
      danmaku: DanmakuRegistry({SiteIds.bilibili: () => danmaku}),
      store: store,
    );
  });
  tearDown(() => store.close());

  /// Every kind of message the room may send, in order.
  void emitAll() {
    danmaku.chat('你好', user: '甲');
    for (final message in [
      _gift('小心心'),
      _gift('辣条', user: '捣乱的'), // a blocked viewer
      _gift('广告礼物'), // a blocked word
      _gift('本地辣条', local: true), // the local interaction's (never from a platform, but kept out)
      _gift('旧礼物', withGift: false), // no LiveGift: nothing to write
      _superChat,
      const LiveMessage(type: LiveMessageType.notice, userName: '', message: '公告', color: LiveMessageColor.white),
    ]) {
      danmaku.emit(DanmakuReceived(message));
    }
  }

  test('off (the default): only the chat reaches the file, as before', () async {
    expect(store.settings.get(Settings.recordDanmakuGifts), isFalse);
    final received = <LiveMessage>[];
    final connection = await connect(_task(), onMessage: received.add, onEnded: () {});
    addTearDown(connection!.stop);
    emitAll();
    expect(received.map((message) => message.type), [LiveMessageType.chat]);
  });

  test('on: gifts through the gift filter (blocked viewers and words), super chats unfiltered', () async {
    await store.blockLists.add(BlockKind.user, '捣乱的');
    await store.blockLists.add(BlockKind.keyword, '广告');
    await store.settings.set(Settings.recordDanmakuGifts, true);
    final received = <LiveMessage>[];
    final connection = await connect(_task(), onMessage: received.add, onEnded: () {});
    addTearDown(connection!.stop);
    emitAll();
    expect(received.map((message) => message.message), ['你好', '小心心 ×1', 'SUPER_CHAT_MESSAGE']);

    // Read for each message: switched off during a recording, the gifts stop.
    await store.settings.set(Settings.recordDanmakuGifts, false);
    danmaku.emit(DanmakuReceived(_gift('花')));
    expect(received, hasLength(3));
  });

  test('the recorder settings carry the switch; the pre-M8.1 object round-trips it', () async {
    expect(RecordSettingsStore.of(store.settings).recordDanmakuGifts, isFalse);
    await store.settings.set(Settings.recordDanmakuGifts, true);
    expect(RecordSettingsStore.of(store.settings).recordDanmakuGifts, isTrue);
    final values = RecordSettingsStore.toValues(RecordSettings(recordDanmakuGifts: true));
    expect(values[Settings.recordDanmakuGifts.key], isTrue);
    expect(RecordSettingsStore.fromValues(values).recordDanmakuGifts, isTrue);
    expect(RecordSettingsStore.fromValues(const {}).recordDanmakuGifts, isFalse);
    expect({for (final setting in Settings.recorder) setting.key}, values.keys.toSet());
  });

  test("the recorded price's yuan units are the gift line's; the combo rules are one", () {
    expect(recordYuanUnits, giftYuanUnits);
    expect(identical(app.giftComboKey, giftComboKey), isTrue);
    expect(identical(app.giftIsComboSummary, giftIsComboSummary), isTrue);
  });

  test('settings search finds the switch, in the recording settings', () {
    for (final query in ['礼物 录制', '醒目留言', 'xml']) {
      final found = searchSettings(settingsCatalog, query);
      final entry = found.singleWhere((entry) => entry.id == 'record_danmaku_gifts', orElse: () => throw query);
      expect(entry.section, SettingsSection.recording);
      expect(entry.settings, [Settings.recordDanmakuGifts]);
      expect(entry.crumb, '录制 › 基础配置');
    }
  });
}
