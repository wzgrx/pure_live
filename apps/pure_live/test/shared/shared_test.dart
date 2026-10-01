import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/shared/rooms/share_code.dart';

import '../support.dart';

LiveRoom _room({
  String platform = 'douyu',
  String id = '1',
  LiveStatus status = LiveStatus.live,
  LiveRestriction? restriction,
  DateTime? startedAt,
  String title = 'title',
}) => LiveRoom(
  platform: platform,
  roomId: id,
  title: title,
  nick: 'anchor',
  link: 'https://www.douyu.com/$id',
  introduction: 'about the room',
  liveStatus: status,
  restriction: restriction,
  startedAt: startedAt,
  popularity: '123456',
);

void main() {
  setUpAll(loadStrings);

  group('texts', () {
    test('room marks: retired platform, carousel, ban, then the restriction', () {
      expect(roomMark(_room(platform: 'huajiao')), '平台已下线');
      expect(roomMark(_room(status: LiveStatus.carousel)), '轮播');
      expect(roomMark(_room(status: LiveStatus.banned)), '已封禁');
      expect(roomMark(_room(restriction: LiveRestriction.subscribersOnly)), '订阅专享');
      expect(roomMark(_room()), isNull);
      expect(restrictionLabel(LiveRestriction.none), isNull);
      expect(restrictionReason(LiveRestriction.paid), contains('付费直播'));
    });

    test('audience counts and load failures', () async {
      expect(readableAudience('123456'), '12.3万');
      expect(readableAudience('999'), '999');
      expect(readableAudience('LIVE'), 'LIVE');
      expect(describeLoadError(const NeedsLogin('douyu')), i18n('load_error_login'));
      expect(describeLoadError(const RiskControl('douyu', cookieSuspect: true)), i18n('load_error_cookie'));
      expect(describeLoadError(const TransportFailure('douyu', TransportReason.timeout)), i18n('load_error_network'));
      expect(describeLoadError(StateError('x')), i18n('load_error_unknown'));
      expect(isLoginError(const RiskControl('douyu')), isTrue);
      final english = await loadStrings(AppLanguage.en);
      expect(english.language, AppLanguage.en);
      expect(readableAudience('15000'), '15.0k');
      expect(readableAudience('5.6万'), '56.0k');
      await loadStrings();
    });
  });

  group('cards', () {
    test('a card: the platform for a missing title and streamer, time on air, the mark', () {
      const policy = AudiencePolicy(preferRealOnline: false, realOnlinePlatforms: {});
      final now = DateTime.utc(2026, 10, 1, 12);
      final card = policy.cardOf(
        _room(title: ' ', restriction: LiveRestriction.paid, startedAt: now.subtract(const Duration(minutes: 75))),
        now: now,
      );
      expect(card.title, '未命名直播间');
      expect(card.anchorName, 'anchor · 已播 1 小时 15 分');
      expect(card.audience, const RoomAudience(kind: RoomAudienceKind.popularity, value: '12.3万'));
      expect(card.restrictionLabel, '付费');
      expect(policy.cardOf(_room()).anchorName, 'anchor');
    });

    test('card settings: phone or desktop, preset or stored, unreadable stored values fall back', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      await store.settings.set(Settings.roomCardMobilePreset, 'compact');
      expect(cardAppearanceOf(store.settings, phone: true), RoomCardAppearance.compact);
      expect(cardAppearanceOf(store.settings, phone: false), RoomCardAppearance.fromPreset(RoomCardPreset.standard));
      await store.settings.set(Settings.roomCardDesktopConfig, {'cardBorderRadius': 'x'});
      expect(cardAppearanceOf(store.settings, phone: false), isA<RoomCardAppearance>());
    });
  });

  group('menu', () {
    late List<String> toasts;
    String? copied;

    Future<LiveStore> pumpMenu(WidgetTester tester, {List<RoomMenuAction> actions = const []}) async {
      final store = (await tester.runAsync(() => LiveStore.memory(cipher: FakeCipher())))!;
      toasts = [];
      AppNavigator.toast = toasts.add;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      final strings = (await tester.runAsync(loadStrings))!;
      await tester.pumpWidget(
        LiveUiScope(
          config: LiveUiConfig(strings: strings.ui),
          child: MaterialApp(
            theme: const LiveTheme(primaryColor: Colors.blue).light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showRoomMenu(context, store: store, room: _room(), actions: actions),
                  child: const Text('open menu'),
                ),
              ),
            ),
          ),
        ),
      );
      return store;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    testWidgets('details with the introduction; copy link, share code and a page action', (tester) async {
      var removed = 0;
      final store = await pumpMenu(
        tester,
        actions: [
          RoomMenuAction(
            key: const ValueKey('page-action'),
            icon: Icons.delete_outline,
            label: 'remove',
            onSelected: () => removed++,
          ),
        ],
      );
      await tester.tap(find.text('open menu'));
      await settle(tester);
      expect(find.byKey(const ValueKey('room-menu-intro')), findsOneWidget);
      expect(find.text('斗鱼'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('room-menu-copy')));
      await settle(tester);
      expect(copied, 'https://www.douyu.com/1');

      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('room-menu-share')));
      await settle(tester);
      expect(copied, encodeRoomShareCode(_room()));
      expect(toasts.last, '已复制到剪贴板');

      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-action')));
      await settle(tester);
      expect(removed, 1);
      await tester.runAsync(store.close);
    });

    testWidgets('tags of a room not followed: follow first, then a new tag from the tag editor', (tester) async {
      final store = await pumpMenu(tester);
      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('room-menu-tags')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('room-tags-follow')));
      await settle(tester);
      expect(await tester.runAsync(() => store.follows.contains(_room())), isTrue);
      expect(toasts, contains('已关注 anchor'));

      expect(find.text(i18n('room_tags_empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-tags-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), '常看');
      await tester.tap(find.byKey(const ValueKey('tag-editor-confirm')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('room-tags-save')));
      await settle(tester);
      final tags = (await tester.runAsync(store.tags.all))!;
      expect(tags.map((tag) => tag.name), ['常看']);
      expect(await tester.runAsync(() => store.tags.tagsOf(_room())), [tags.single.id]);

      // Unfollow asks, then can be undone.
      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('room-menu-follow')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('unfollow-confirm')));
      await settle(tester);
      expect(await tester.runAsync(() => store.follows.contains(_room())), isFalse);
      await tester.tap(find.text('撤销'));
      await settle(tester);
      expect(await tester.runAsync(() => store.follows.contains(_room())), isTrue);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.runAsync(store.close);
    });
  });

  group('start-up', () {
    test('the Bilibili login: a valid one keeps its uid, an expired one is signed out', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final toasts = <String>[];
      AppNavigator.toast = toasts.add;
      final actions = AccountActions(store);
      Future<AccountIdentity> valid(String site, String cookie) async => (name: 'me', uid: 42);
      Future<AccountIdentity> expired(String site, String cookie) async => throw const NeedsLogin('bilibili');
      Future<AccountIdentity> offline(String site, String cookie) async =>
          throw const TransportFailure('bilibili', TransportReason.timeout);

      await verifyBilibiliLogin(actions: actions, verify: expired);
      expect(toasts, isEmpty); // no cookie, nothing to check

      await actions.save(SiteIds.bilibili, 'SESSDATA=a');
      await verifyBilibiliLogin(actions: actions, verify: valid);
      expect(store.settings.get(Settings.bilibiliUid), 42);

      await verifyBilibiliLogin(actions: actions, verify: offline);
      expect(toasts.single, i18n('bilibili_user_info_failed'));
      expect(actions.cookieOf(SiteIds.bilibili), 'SESSDATA=a');

      await verifyBilibiliLogin(actions: actions, verify: expired);
      expect(toasts.last, i18n('bilibili_login_expired'));
      expect(actions.cookieOf(SiteIds.bilibili), isEmpty);
      expect(store.settings.get(Settings.bilibiliUid), 0);
    });
  });
}
