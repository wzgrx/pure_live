// Phrases and recent sends (docs/D-弹幕/D08-本地互动/D08.2-常用语和最近发送): the
// chips over the local danmaku composer (the last 5 different local danmaku,
// then the phrases), a tap sends, a long press fills the field; "存为常用语"
// in a local danmaku's panel; the settings page's group: add, change,
// delete with undo, reorder; the same in every composer, at large text.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_composer.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_settings_page.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import 'local_interaction_support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

LocalRoomSession _session(WidgetTester tester) => LocalRoomScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!;

const LocalPlace _here = (platform: SiteIds.bilibili, roomId: '6', roomName: '主播');

/// The chips' words, left to right.
List<String> _chips(WidgetTester tester) {
  final chips = find.descendant(of: _key('local-composer-chips'), matching: find.byType(ActionChip));
  final found = [
    for (final element in chips.evaluate())
      (
        tester.getTopLeft(find.byWidget(element.widget)).dx,
        tester.widget<Text>(find.descendant(of: find.byWidget(element.widget), matching: find.byType(Text)).last).data!,
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, words) in found) words];
}

List<String> _localWords(WidgetTester tester) => [
  for (final line in _session(tester).room.chat.lines)
    if (line.message case final message? when message.isLocal) message.message,
];

Future<void> _focus(WidgetTester tester, String field) async {
  await tester.tap(_in(field, find.byType(EditableText)));
  await tester.pump();
}

/// Sends [texts] in order through the session, as the composer does.
void _sendAll(WidgetTester tester, List<String> texts) {
  for (final text in texts) {
    expect(_session(tester).sendChat(text), isTrue);
  }
}

void _textScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// The chips sit over the field, both inside the view.
void _chipsOver(WidgetTester tester, String field, Size view) {
  final chips = tester.getRect(_key('local-composer-chips'));
  final box = tester.getRect(_in(field, find.byType(EditableText)));
  expect(chips.bottom, lessThanOrEqualTo(box.top), reason: 'over the field');
  expect(chips.top, greaterThanOrEqualTo(0));
  expect(box.bottom, lessThanOrEqualTo(view.height), reason: 'the field stays on the screen');
  expect(chips.left, greaterThanOrEqualTo(0));
  expect(chips.right, lessThanOrEqualTo(view.width));
}

void main() {
  group('logic', () {
    late LiveStore store;
    late LocalInteraction local;
    setUp(() async {
      store = await LiveStore.memory(cipher: FakeCipher());
      await loadStrings();
      local = LocalInteraction(store.settings, events: store.localEvents);
      await local.start();
    });
    tearDown(() async {
      // The entries are written after they show.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      local.dispose();
      await store.close();
    });

    test('recent: the last 5 different local danmaku, newest first; not the phrases; not gifts or coins', () {
      expect(local.recentChats(), isEmpty);
      for (final text in ['一', '二', '三', '二', ' 四 ', '五', '六', '六']) {
        local.recordChat(text, _here);
      }
      local
        ..recharge(500)
        ..sendGift(LocalCatalog.giftsFor(SiteIds.bilibili).first, platform: SiteIds.bilibili, place: _here);
      expect(local.recentChats(), ['六', '五', '四', '二', '三']);
      expect(local.addPhrase('五'), isTrue);
      expect(local.recentChats(), ['六', '四', '二', '三', '一'], reason: 'a phrase has its own chip');
    });

    test('phrases: added at the end, trimmed and cut to 40 characters, no repeats, at most 20', () {
      expect(local.phrases, isEmpty);
      expect(local.addPhrase('  主播晚上好 '), isTrue);
      expect(local.addPhrase('主播晚上好'), isFalse);
      expect(local.phraseProblem('主播晚上好'), LocalPhraseProblem.exists);
      expect(local.phraseProblem('   '), LocalPhraseProblem.empty);
      final long = '${'长' * 39}😀${'多' * 10}';
      expect(local.addPhrase(long), isTrue);
      expect(local.phrases, ['主播晚上好', '${'长' * 39}😀']);
      expect(local.phrases.last.characters.length, LocalCatalog.danmakuLimit);
      expect(local.hasPhrase(' 主播晚上好'), isTrue);
      for (var i = 0; local.phrases.length < Settings.localPhraseLimit; i++) {
        expect(local.addPhrase('第$i句'), isTrue);
      }
      expect(local.phrasesFull, isTrue);
      expect(local.phraseProblem('再来一句'), LocalPhraseProblem.full);
      expect(local.addPhrase('再来一句'), isFalse);
      expect(local.phrases, hasLength(20));
      expect(local.phraseProblem('第0句', replacing: 2), isNull, reason: 'the same one changed in place');
    });

    test('phrases: changed, moved, removed and put back; stored in the setting', () async {
      for (final text in ['一', '二', '三']) {
        local.addPhrase(text);
      }
      expect(local.editPhrase(1, '贰'), isTrue);
      expect(local.editPhrase(1, '一'), isFalse, reason: 'a repeat');
      local.movePhrase(0, 2);
      expect(local.phrases, ['贰', '三', '一']);
      final removed = local.removePhrase(1);
      expect(removed, '三');
      expect(local.phrases, ['贰', '一']);
      local.restorePhrase(1, removed!);
      expect(local.phrases, ['贰', '三', '一']);
      local.restorePhrase(0, '三');
      expect(local.phrases, ['贰', '三', '一'], reason: 'not twice');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.settings.get(Settings.localInteractionPhrases), ['贰', '三', '一']);
    });

    test('a restored backup with a long phrase: read cut to 40 characters', () async {
      await store.settings.set(Settings.localInteractionPhrases, ['短', '长' * 60, '${'长' * 40}尾']);
      expect(local.phrases, ['短', '长' * 40], reason: 'cut, and the two the same once cut');
    });
  });

  group('the composer\'s chips (c1, c2)', () {
    testWidgets('portrait: none without the focus or without anything; then the recent 5 and the phrases', (
      tester,
    ) async {
      final room = await pumpLocalRoom(tester);
      final height = tester.getSize(_key('local-composer-bar')).height;
      await _focus(tester, 'local-composer-bar');
      expect(_key('local-composer-chips'), findsNothing, reason: 'nothing sent, no phrases');
      expect(tester.getSize(_key('local-composer-bar')).height, height, reason: 'no gap either');
      _sendAll(tester, ['一', '二', '三', '二', '四', '五', '六']);
      await tester.pump();
      expect(_chips(tester), ['六', '五', '四', '二', '三']);
      expect(_in('local-chip-recent-0', find.byIcon(AppIcons.localRecent)), findsOneWidget);
      _session(tester).interaction
        ..addPhrase('主播晚上好')
        ..addPhrase('666');
      await tester.pump();
      expect(_chips(tester), ['六', '五', '四', '二', '三', '主播晚上好', '666']);
      expect(_in('local-chip-phrase-0', find.byIcon(AppIcons.localRecent)), findsNothing);
      _chipsOver(tester, 'local-composer-bar', const Size(400, 900));
      expect(
        tester.getRect(_key('local-composer-chips')).top,
        greaterThanOrEqualTo(tester.getRect(_key('local-composer-bar')).top),
        reason: 'inside the bar, the list above gives way',
      );

      // The focus goes: so do the chips.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(_key('local-composer-chips'), findsNothing);
      await closeLocalRoom(tester, room);
    });

    testWidgets('a tap sends the chip (what is typed stays); a long press puts it in the field', (tester) async {
      final room = await pumpLocalRoom(tester);
      _session(tester).interaction.addPhrase('主播晚上好');
      await tester.pump();
      await _focus(tester, 'local-composer-bar');
      await tester.enterText(_in('local-composer-bar', find.byType(EditableText)), '打了一半');
      await tester.pump();
      await tester.tap(_key('local-chip-phrase-0'));
      await tester.pump();
      expect(_localWords(tester), ['主播晚上好']);
      expect(_session(tester).interaction.events.first.text, '主播晚上好', reason: 'recorded (D08.1)');
      final field = tester.widget<EditableText>(_in('local-composer-bar', find.byType(EditableText)));
      expect(field.controller.text, '打了一半');
      expect(field.focusNode.hasFocus, isTrue, reason: 'still typing');
      // Now it is recent as well as a phrase: once.
      expect(_chips(tester), ['主播晚上好']);

      await tester.longPress(_key('local-chip-phrase-0'));
      await tester.pump();
      expect(field.controller.text, '主播晚上好');
      expect(field.controller.selection, const TextSelection.collapsed(offset: 5), reason: 'the cursor at the end');
      expect(_localWords(tester), ['主播晚上好'], reason: 'not sent');
      await tester.tap(_in('local-composer-bar', _key('local-composer-send')));
      await tester.pump();
      expect(_localWords(tester), ['主播晚上好', '主播晚上好']);
      await closeLocalRoom(tester, room);
    });

    testWidgets('the local interaction panel\'s composer: the same chips', (tester) async {
      final room = await pumpLocalRoom(tester);
      _sendAll(tester, ['晚上好']);
      await tester.tap(_key('live-play-menu'));
      await tester.pumpAndSettle();
      await tester.tap(_key('room-menu-localInteraction'));
      await tester.pumpAndSettle();
      await _focus(tester, 'local-panel-composer');
      expect(_in('local-panel-composer', _key('local-composer-chips')), findsOneWidget);
      expect(_chips(tester), ['晚上好']);
      _chipsOver(tester, 'local-panel-composer', const Size(400, 900));
      await tester.tap(_key('local-chip-recent-0'));
      await tester.pump();
      expect(_localWords(tester), ['晚上好', '晚上好']);
      await closeLocalRoom(tester, room);
    });

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('landscape fullscreen ×$scale: the chips float above the field on the picture; a tap flies', (
        tester,
      ) async {
        _textScale(tester, scale);
        final room = await pumpLocalRoom(tester, width: 852, height: 393);
        _sendAll(tester, ['前排', '晚上好']);
        _session(tester).interaction.addPhrase('${'很长的一句常用语' * 4}好');
        await tester.tap(_key('live-play-fullscreen'));
        await tester.pump();
        // The controls hide after 4 s of quiet; the field holds them up.
        await tester.pump(const Duration(seconds: 1));
        final video = _key('local-composer-video');
        expect(video, findsOneWidget);
        await _focus(tester, 'local-composer-video');
        expect(_chips(tester), ['晚上好', '前排', '${'很长的一句常用语' * 4}好']);
        _chipsOver(tester, 'local-composer-video', const Size(852, 393));
        final chips = tester.getRect(_key('local-composer-chips'));
        expect(chips.width, lessThanOrEqualTo(tester.getRect(video).width + 0.5), reason: 'as wide as the field');
        expect(
          tester.getSize(_key('local-chip-phrase-0')).width,
          lessThan(LocalComposerChips.chipMaxWidth + 80),
          reason: 'a long phrase ends in "…"',
        );
        // The picture's words grow 1.3 times at most.
        final text = tester.widget<Text>(_in('local-chip-recent-0', find.byType(Text)).last);
        expect(
          MediaQuery.textScalerOf(tester.element(find.byWidget(text))).scale(10),
          moreOrLessEquals(10 * (scale > 1.3 ? 1.3 : scale)),
        );
        final flying = tester.state<DanmakuOverlayState>(find.byType(DanmakuOverlay));
        final before = flying.flyingCount;
        await tester.tap(_key('local-chip-recent-1'));
        await tester.pump();
        expect(_localWords(tester).last, '前排');
        expect(flying.flyingCount, before + 1);
        expect(_key('live-play-back'), findsOneWidget, reason: 'still in the fullscreen');
        await closeLocalRoom(tester, room);
      });

      testWidgets('portrait ×$scale: the bar with the chips stays on the screen', (tester) async {
        _textScale(tester, scale);
        final room = await pumpLocalRoom(tester);
        _sendAll(tester, ['一', '二', '三']);
        _session(tester).interaction.addPhrase('主播晚上好');
        await tester.pump();
        await _focus(tester, 'local-composer-bar');
        expect(_chips(tester), ['三', '二', '一', '主播晚上好']);
        _chipsOver(tester, 'local-composer-bar', const Size(400, 900));
        expect(tester.getRect(_key('local-composer-bar')).bottom, 900);
        await closeLocalRoom(tester, room);
      });

      testWidgets('the narrow fullscreen bar (<180) ×$scale: the row it opens has the chips over it', (tester) async {
        _textScale(tester, scale);
        final session = ValueNotifier<LocalRoomSession?>(null);
        final room = await pumpLocalRoom(
          tester,
          width: 852,
          height: 393,
          wrap: (page) => Stack(
            children: [
              page,
              Positioned(
                left: 300,
                bottom: 0,
                child: ValueListenableBuilder(
                  valueListenable: session,
                  builder: (context, value, _) => value == null
                      ? const SizedBox.shrink()
                      : SizedBox(
                          key: const ValueKey('narrow-bar'),
                          width: 150,
                          height: 52,
                          child: LocalDanmakuComposer(place: LocalComposerPlace.video, session: value),
                        ),
                ),
              ),
            ],
          ),
        );
        session.value = _session(tester);
        _sendAll(tester, ['前排']);
        _session(tester).interaction.addPhrase('主播晚上好');
        await tester.pump();
        expect(_in('narrow-bar', _key('local-composer-star')), findsOneWidget, reason: 'collapsed');
        await tester.tap(_in('narrow-bar', _key('local-composer-star')));
        await tester.pumpAndSettle();
        final row = _key('local-composer-row');
        expect(row, findsOneWidget);
        expect(_chips(tester), ['前排', '主播晚上好'], reason: 'the row has the focus');
        _chipsOver(tester, 'local-composer-row', const Size(852, 393));
        await tester.tap(_key('local-chip-phrase-0'));
        await tester.pumpAndSettle();
        expect(row, findsNothing, reason: 'sent: the row closes, as after Enter');
        expect(_localWords(tester), ['前排', '主播晚上好']);
        await closeLocalRoom(tester, room);
      });
    }
  });

  group('"存为常用语" (c3)', () {
    testWidgets('one\'s own local danmaku: saved, then "已在常用语里"; a platform\'s has none', (tester) async {
      final room = await pumpLocalRoom(tester);
      _sendAll(tester, ['主播晚上好']);
      await tester.pump();
      await tester.longPress(_key('live-play-local-line'));
      await tester.pumpAndSettle();
      final save = _key('live-play-save-phrase');
      expect(_in('live-play-save-phrase', find.text('存为常用语')), findsOneWidget);
      expect(_in('live-play-save-phrase', find.byIcon(AppIcons.localPhraseSave)), findsOneWidget);
      expect(
        tester.getTopLeft(save).dy,
        greaterThan(tester.getTopLeft(_key('live-play-send-local-again')).dy),
        reason: 'under "再发一次" (A08.14)',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(_key('live-play-message-panel'), findsNothing);
      expect(room.toasts, ['已存为常用语']);
      expect(_session(tester).interaction.phrases, ['主播晚上好']);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(room.settings.get(Settings.localInteractionPhrases), ['主播晚上好']);

      await tester.longPress(_key('live-play-local-line'));
      await tester.pumpAndSettle();
      expect(_in('live-play-save-phrase', find.text('已在常用语里')), findsOneWidget);
      expect(_in('live-play-save-phrase', find.byIcon(AppIcons.localPhraseSaved)), findsOneWidget);
      expect(tester.widget<ListTile>(save).enabled, isFalse);
      RoomPanelScope.maybeOf(tester.element(find.byType(DanmakuOverlay)))!.close();
      await tester.pumpAndSettle();

      room.danmaku.chat('别人的话', user: '路人', id: 'p1');
      await settleLocal(tester);
      await tester.longPress(find.textContaining('别人的话', findRichText: true).first);
      await tester.pumpAndSettle();
      expect(_key('live-play-send-local-again'), findsOneWidget);
      expect(save, findsNothing, reason: 'only one\'s own words');
      await closeLocalRoom(tester, room);
    });

    testWidgets('with 20 phrases: it says so and cannot be tapped', (tester) async {
      final room = await pumpLocalRoom(
        tester,
        settings: {
          Settings.localInteractionPhrases: [for (var i = 0; i < 20; i++) '第$i句'],
        },
      );
      _sendAll(tester, ['新的一句']);
      await tester.pump();
      await tester.longPress(_key('live-play-local-line'));
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(_key('live-play-save-phrase')).enabled, isFalse);
      expect(_in('live-play-save-phrase', find.textContaining('常用语最多 20 条')), findsOneWidget);
      await closeLocalRoom(tester, room);
    });
  });

  group('settings page (c4)', () {
    Future<AppServices> pumpSettings(WidgetTester tester, {List<String> phrases = const []}) async {
      tester.view
        ..physicalSize = const Size(400, 3000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(() async {
        final services = await testServices();
        if (phrases.isNotEmpty) await services.store.settings.set(Settings.localInteractionPhrases, phrases);
        return services;
      }))!;
      await tester.runAsync(loadStrings);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: MaterialApp(
            theme: const LiveTheme().light,
            builder: (context, child) =>
                MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
            home: const LocalInteractionSettingsPage(),
          ),
        ),
      );
      await settleLocal(tester);
      return services;
    }

    Future<void> close(WidgetTester tester, AppServices services) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(services.close);
    }

    List<String> rows(WidgetTester tester) => [
      for (var i = 0; _key('local-phrase-row-$i').evaluate().isNotEmpty; i++)
        tester.widget<Text>(_in('local-phrase-row-$i', find.byType(Text))).data!,
    ];

    testWidgets('its place, empty at first, add one (no repeats, 40 characters), change it', (tester) async {
      final services = await pumpSettings(tester);
      final titles = ['画面上', '常用语', '平台体验资源包'];
      final tops = [for (final title in titles) tester.getTopLeft(find.text(title)).dy];
      expect(tops, [...tops]..sort(), reason: 'after "画面上"');
      expect(_key('local-phrases-empty'), findsOneWidget);
      expect(tester.widget<Text>(_key('local-phrases-count')).data, '0 / 20');

      await tester.tap(_key('local-phrase-add'));
      await tester.pumpAndSettle();
      expect(find.text('添加常用语'), findsWidgets);
      expect(tester.widget<TextField>(_key('local-phrase-input')).maxLength, LocalCatalog.danmakuLimit);
      await tester.enterText(_key('local-phrase-input'), ' 主播晚上好 ');
      await tester.pump();
      await tester.tap(_key('local-phrase-confirm'));
      await tester.pumpAndSettle();
      expect(rows(tester), ['主播晚上好']);
      expect(_key('local-phrases-empty'), findsNothing);

      await tester.tap(_key('local-phrase-add'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('local-phrase-input'), '主播晚上好');
      await tester.pump();
      await tester.tap(_key('local-phrase-confirm'));
      await tester.pumpAndSettle();
      expect(find.text('已经有这条常用语了'), findsOneWidget, reason: 'the dialog stays and says why');
      await tester.enterText(_key('local-phrase-input'), '666');
      await tester.pump();
      await tester.tap(_key('local-phrase-confirm'));
      await tester.pumpAndSettle();
      expect(rows(tester), ['主播晚上好', '666']);

      await tester.tap(_key('local-phrase-row-1'));
      await tester.pumpAndSettle();
      expect(find.text('修改常用语'), findsOneWidget);
      expect(tester.widget<TextField>(_key('local-phrase-input')).controller!.text, '666');
      await tester.enterText(_key('local-phrase-input'), '777');
      await tester.pump();
      await tester.tap(_key('local-phrase-confirm'));
      await tester.pumpAndSettle();
      expect(rows(tester), ['主播晚上好', '777']);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(services.store.settings.get(Settings.localInteractionPhrases), ['主播晚上好', '777']);
      await close(tester, services);
    });

    testWidgets('delete: gone at once, undone from the toast for 4 s', (tester) async {
      final services = await pumpSettings(tester, phrases: ['一', '二', '三']);
      expect(rows(tester), ['一', '二', '三']);
      await tester.tap(_key('local-phrase-delete-1'));
      await tester.pump();
      expect(rows(tester), ['一', '三']);
      final toast = find.byKey(const ValueKey('local-phrase-undo'));
      expect(toast, findsOneWidget);
      expect(find.textContaining('已删除常用语“二”'), findsOneWidget);
      expect(tester.widget<SnackBar>(toast).duration, AppToast.actionDuration);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_in('local-phrase-undo', find.text('撤销')));
      await tester.pumpAndSettle();
      expect(rows(tester), ['一', '二', '三'], reason: 'back in its place');
      await close(tester, services);
    });

    testWidgets('reorder by the handle; with 20 "添加常用语" is off and says so', (tester) async {
      final services = await pumpSettings(tester, phrases: ['一', '二', '三']);
      final gesture = await tester.startGesture(tester.getCenter(_key('local-phrase-handle-0')));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 14));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(rows(tester), ['二', '三', '一']);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(services.store.settings.get(Settings.localInteractionPhrases), ['二', '三', '一']);

      await tester.runAsync(
        () => services.store.settings.set(Settings.localInteractionPhrases, [for (var i = 0; i < 20; i++) '第$i句']),
      );
      await settleLocal(tester);
      expect(tester.widget<TextButton>(_key('local-phrase-add')).onPressed, isNull);
      expect(tester.widget<Text>(_key('local-phrases-count')).data, '常用语最多 20 条，先删掉一些');
      await close(tester, services);
    });
  });
}
