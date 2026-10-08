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
      expect(policy.cardOf(_room()).introLine, isNull, reason: 'a title of its own: the streamer as before');
    });

    test('A09.11: a title that is the streamer shows the first line of the introduction instead', () {
      const policy = AudiencePolicy(preferRealOnline: false, realOnlinePlatforms: {});
      LiveRoom channel(String title, String? introduction) =>
          _room(title: title).copyWith(introduction: introduction ?? '');
      expect(policy.cardOf(channel('anchor', 'about the room')).introLine, 'about the room');
      expect(policy.cardOf(channel(' Anchor ', 'about')).introLine, 'about', reason: 'case and spaces aside');
      expect(policy.cardOf(channel('anchor', '\n  \nfirst line  \nsecond')).introLine, 'first line');
      expect(policy.cardOf(channel('anchor', '  ')).introLine, isNull, reason: 'no introduction: the name');
      expect(policy.cardOf(channel('anchor', null)).introLine, isNull);
      expect(policy.cardOf(channel('anchor tonight', 'about')).introLine, isNull, reason: 'a title of its own');
      final card = policy.cardOf(channel('anchor', 'about'));
      expect(card.anchorName, 'anchor', reason: "the avatar's letter and the rows keep the name");
      final now = DateTime.utc(2026, 10, 1, 12);
      expect(
        policy
            .cardOf(
              _room(title: 'anchor', startedAt: now.subtract(const Duration(minutes: 5))),
              now: now,
            )
            .introLine,
        'about the room · 已播 5 分钟',
        reason: 'the time on air follows, as after the name',
      );
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

    Future<LiveStore> pumpMenu(
      WidgetTester tester, {
      List<RoomMenuAction> actions = const [],
      Size size = const Size(393, 852),
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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

    testWidgets('U.4a c10, c11: the dialog: streamer, platform and room, the title, share and tags, close and follow', (
      tester,
    ) async {
      var removed = 0;
      final store = await pumpMenu(
        tester,
        actions: [
          RoomMenuAction(
            key: const ValueKey('page-action'),
            icon: AppIcons.delete,
            label: 'remove',
            onSelected: () => removed++,
          ),
        ],
      );
      await tester.tap(find.text('open menu'));
      await settle(tester);
      // A dialog in the middle (choice A1), as wide as 3.x's at most.
      final dialog = find.byKey(const ValueKey('room-menu'));
      expect(dialog, findsOneWidget);
      expect(tester.getCenter(dialog).dx, closeTo(393 / 2, 1));
      expect(find.text('anchor'), findsOneWidget);
      expect(find.text('斗鱼 · 房间号 1'), findsOneWidget);
      expect(find.text('title'), findsOneWidget);
      // Share and tags carry their words, share first; then close and the follow pill.
      final share = find.byKey(const ValueKey('room-menu-share'));
      final tags = find.byKey(const ValueKey('room-menu-tags'));
      expect(find.descendant(of: share, matching: find.text('分享')), findsOneWidget);
      expect(find.descendant(of: tags, matching: find.text('设置标签')), findsOneWidget);
      expect(tester.getCenter(share).dx, lessThan(tester.getCenter(tags).dx));
      final close = find.byKey(const ValueKey('card-dialog-close'));
      final follow = find.byKey(const ValueKey('room-menu-follow'));
      expect(tester.getCenter(close).dx, lessThan(tester.getCenter(follow).dx));
      expect(find.descendant(of: follow, matching: find.text('关注')), findsOneWidget);
      expect(find.descendant(of: follow, matching: find.byIcon(AppIcons.follow)), findsOneWidget);
      // 3.x had no "open" or "copy link" here: a tap on the card opens the room.
      expect(find.byKey(const ValueKey('room-menu-copy')), findsNothing);
      expect(find.byKey(const ValueKey('room-menu-open')), findsNothing);

      await tester.tap(share);
      await settle(tester);
      expect(copied, encodeRoomShareCode(_room()));
      expect(toasts.last, '已复制到剪贴板');

      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('page-action')));
      await settle(tester);
      expect(removed, 1);

      // Follow closes the dialog and says so; the pill then reads "✓ 已关注".
      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(follow);
      await settle(tester);
      expect(find.byKey(const ValueKey('room-menu')), findsNothing);
      expect(toasts.last, '已关注 anchor');
      await tester.tap(find.text('open menu'));
      await settle(tester);
      expect(find.descendant(of: follow, matching: find.text('已关注')), findsOneWidget);
      // Esc closes it (as Back does).
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byKey(const ValueKey('room-menu')), findsNothing);
      await tester.runAsync(store.close);
    });

    testWidgets('U.4a c12, c13: tags of a room not followed: follow first, tags made in place, unfollow undone', (
      tester,
    ) async {
      final store = await pumpMenu(tester);
      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('room-menu-tags')));
      await settle(tester);
      // One dialog that says why, its button says what it does.
      expect(find.text('先关注再设置标签'), findsOneWidget);
      expect(find.text('关注并设置标签'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-tags-follow')));
      await settle(tester);
      expect(await tester.runAsync(() => store.follows.contains(_room())), isTrue);
      expect(toasts, contains('已关注 anchor'));

      // No tags: says which room, the form is open from the start.
      expect(find.text('anchor · 斗鱼'), findsOneWidget);
      expect(find.text('还没有标签'), findsOneWidget);
      expect(find.byKey(const ValueKey('room-tags-form')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-tags-add')));
      await settle(tester);
      expect(find.text(i18n('tag_name_empty_error')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('room-tags-name')), '常看');
      await tester.pump();
      expect(find.text('2/15'), findsOneWidget);
      // I03.2 c8: the store's limits, the same as the tag editor's.
      expect(tester.widget<TextField>(find.byKey(const ValueKey('room-tags-name'))).maxLength, TagStore.maxNameLength);
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('room-tags-note'))).maxLength,
        TagStore.maxDescriptionLength,
      );
      await tester.tap(find.byKey(const ValueKey('room-tags-add')));
      await settle(tester);
      // Listed and selected; the form is cleared and stays for the next one.
      final tags = (await tester.runAsync(store.tags.all))!;
      expect(tags.map((tag) => tag.name), ['常看']);
      expect(find.byKey(ValueKey('tag-choice-${tags.single.id}')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('room-tags-name')), '常看');
      await tester.tap(find.byKey(const ValueKey('room-tags-add')));
      await settle(tester);
      expect(find.text(i18n('tag_name_duplicate_error')), findsOneWidget);
      // "保存" first makes a name still typed into a tag, then saves.
      await tester.enterText(find.byKey(const ValueKey('room-tags-name')), '睡前听');
      // The main button says what it does (U.1d; not "确认").
      expect(
        find.descendant(of: find.byKey(const ValueKey('room-tags-save')), matching: find.text('保存')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('room-tags-save')));
      await settle(tester);
      expect(find.byKey(const ValueKey('room-tags')), findsNothing);
      final saved = (await tester.runAsync(store.tags.all))!;
      expect(saved.map((tag) => tag.name), ['常看', '睡前听']);
      expect(await tester.runAsync(() => store.tags.tagsOf(_room())), [for (final tag in saved) tag.id]);

      // With tags: "＋ 新建标签" opens the form in place, the list stays; a tap clears a tag.
      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('room-menu-tags')));
      await settle(tester);
      expect(find.byKey(const ValueKey('room-tags-form')), findsNothing);
      expect(find.byKey(const ValueKey('room-tags-columns-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-tags-new')));
      await settle(tester);
      expect(find.byKey(const ValueKey('room-tags-form')), findsOneWidget);
      expect(find.byKey(ValueKey('tag-choice-${saved.first.id}')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-tags-collapse')));
      await settle(tester);
      expect(find.byKey(const ValueKey('room-tags-form')), findsNothing);
      await tester.tap(find.byKey(ValueKey('tag-choice-${saved.first.id}')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('room-tags-save')));
      await settle(tester);
      expect(await tester.runAsync(() => store.tags.tagsOf(_room())), [saved.last.id]);

      // Unfollow asks on top of the dialog (red "取消关注"), then can be undone.
      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('room-menu-follow')));
      await settle(tester);
      expect(find.byKey(const ValueKey('room-menu')), findsOneWidget);
      final confirm = tester.widget<DialogActionButton>(find.byKey(const ValueKey('unfollow-confirm')));
      expect(confirm.danger, isTrue);
      expect(
        find.descendant(of: find.byKey(const ValueKey('unfollow-confirm')), matching: find.text('取消关注')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('unfollow-confirm')));
      await settle(tester);
      expect(find.byKey(const ValueKey('room-menu')), findsNothing);
      expect(await tester.runAsync(() => store.follows.contains(_room())), isFalse);
      await tester.tap(find.text('撤销'));
      await settle(tester);
      expect(await tester.runAsync(() => store.follows.contains(_room())), isTrue);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.runAsync(store.close);
    });

    testWidgets('U.4a c14: tags take two columns when the dialog is wide enough, landscape phones too', (tester) async {
      final store = await pumpMenu(tester, size: const Size(852, 393));
      await tester.runAsync(() async {
        await store.follows.add(_room());
        await store.tags.add('常看');
        await store.tags.add('唱歌');
      });
      await tester.tap(find.text('open menu'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('room-menu-tags')));
      await settle(tester);
      expect(find.byKey(const ValueKey('room-tags-columns-2')), findsOneWidget);
      // The dialog fits the short screen and scrolls inside.
      expect(tester.getSize(find.byKey(const ValueKey('room-tags'))).height, lessThanOrEqualTo(393));
      await tester.tap(find.byKey(const ValueKey('room-tags-cancel')));
      await settle(tester);
      expect(find.byKey(const ValueKey('room-tags')), findsNothing);
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
      // K01.2: the checked login is remembered for switching back to it.
      expect(
        [for (final a in store.accounts.of(SiteIds.bilibili)) (a.uid, a.name, a.cookie)],
        [(42, 'me', 'SESSDATA=a')],
      );

      await verifyBilibiliLogin(actions: actions, verify: offline);
      expect(toasts.single, i18n('bilibili_user_info_failed'));
      expect(actions.cookieOf(SiteIds.bilibili), 'SESSDATA=a');

      await verifyBilibiliLogin(actions: actions, verify: expired);
      expect(toasts.last, i18n('bilibili_login_expired'));
      expect(actions.cookieOf(SiteIds.bilibili), isEmpty);
      expect(store.settings.get(Settings.bilibiliUid), 0);
      expect(store.accounts.of(SiteIds.bilibili), isEmpty, reason: 'an expired login is forgotten with it');
    });
  });
}
