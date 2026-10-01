import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  group('LiveArea', () {
    test('3.x JSON round-trips; missing fields are empty', () {
      const json = {
        'platform': 'douyu',
        'areaType': '1',
        'typeName': '网游竞技',
        'areaId': '1',
        'areaName': '英雄联盟',
        'areaPic': 'https://img.test/lol.png',
        'shortName': 'LOL',
      };
      expect(LiveArea.fromJson(json).toJson(), json);
      expect(LiveArea.fromJson(const {'platform': 'huya'}).areaId, '');
    });

    test('identity is platform and id; Missevan adds its namespace', () {
      const a = LiveArea(platform: 'Douyu', areaId: ' 1 ', areaType: 'x');
      const b = LiveArea(platform: 'douyu', areaId: '1', areaType: 'y');
      expect(a.hasSameIdentity(b), isTrue);
      const catalog = LiveArea(platform: 'missevan', areaId: '5', areaType: 'catalog');
      const tag = LiveArea(platform: 'missevan', areaId: '5', areaType: 'tag');
      expect(catalog.hasSameIdentity(tag), isFalse);
      expect(const LiveArea(platform: 'douyu').identityKey, isNull);
      expect(const LiveArea().hasSameIdentity(const LiveArea()), isFalse);
    });
  });

  group('LiveMessageColor', () {
    test('integers become colours whatever their number of hex digits', () {
      expect(LiveMessageColor.numberToColor(0xFFFFFF), LiveMessageColor.white);
      expect(LiveMessageColor.numberToColor(0x00FF00), const LiveMessageColor(0, 255, 0));
      // 3.x turned these into white.
      expect(LiveMessageColor.numberToColor(0x0000FF), const LiveMessageColor(0, 0, 255));
      expect(LiveMessageColor.numberToColor(0x0A0A0A), const LiveMessageColor(10, 10, 10));
      expect(LiveMessageColor.numberToColor(0x0FFFFF), const LiveMessageColor(15, 255, 255));
      expect(LiveMessageColor.numberToColor(0x0FFF0000), const LiveMessageColor(255, 0, 0));
      expect(LiveMessageColor.numberToColor(-65536), const LiveMessageColor(255, 0, 0), reason: 'signed ARGB');
      expect(LiveMessageColor.numberToColor(0xFF123456), const LiveMessageColor(0x12, 0x34, 0x56));
    });

    test('prints as #rrggbb', () {
      expect(const LiveMessageColor(1, 171, 255).toString(), '#01abff');
    });
  });

  test('super chats are equal by platform id, else by sender, text and price', () {
    LiveSuperChatMessage chat({String id = '', String text = 'hi', int price = 30, DateTime? start}) =>
        LiveSuperChatMessage(
          messageId: id,
          userName: 'u',
          face: '',
          message: text,
          price: price,
          startTime: start ?? DateTime(2026),
          endTime: DateTime(2026, 1, 2),
          backgroundColor: '#fff',
          backgroundBottomColor: '#eee',
        );
    expect(
      chat(start: DateTime(2026)),
      chat(start: DateTime(2027)),
      reason: 'polls rebuild start times',
    );
    expect(chat(id: 'a'), chat(id: 'a', text: 'edited'));
    expect(chat(id: 'a'), isNot(chat(id: 'b')));
    expect(chat(id: 'a'), isNot(chat()));
    expect({chat(), chat()}, hasLength(1));
  });

  test('a super chat can carry the price as the platform shows it', () {
    final at = DateTime.utc(2026, 9, 30);
    LiveSuperChatMessage chat(String text) => LiveSuperChatMessage(
      userName: 'a',
      face: '',
      message: 'hi',
      price: 500,
      startTime: at,
      endTime: at,
      backgroundColor: '',
      backgroundBottomColor: '',
      priceText: text,
    );
    expect(chat(r'$5.00').priceText, r'$5.00');
    expect(
      LiveSuperChatMessage(
        userName: 'a',
        face: '',
        message: 'hi',
        price: 500,
        startTime: at,
        endTime: at,
        backgroundColor: '',
        backgroundBottomColor: '',
      ).priceText,
      isEmpty,
    );
    expect(chat(r'$5.00'), chat(r'NT$5'), reason: 'equality is unchanged: sender, text and price');
  });

  test('a message names no pictures unless given; emotes are equal by code and address', () {
    const plain = LiveMessage(type: LiveMessageType.chat, userName: 'u', message: 'hi', color: LiveMessageColor.white);
    expect(plain.emotes, isEmpty);
    const emote = LiveEmote(code: '{:d_47:}', url: 'https://ssl.pstatic.net/static/nng/glive/icon/b_07.gif');
    const withEmote = LiveMessage(
      type: LiveMessageType.chat,
      userName: 'u',
      message: '{:d_47:}{:d_47:}',
      color: LiveMessageColor.white,
      emotes: [emote],
    );
    expect(
      withEmote.emotes.single,
      const LiveEmote(code: '{:d_47:}', url: 'https://ssl.pstatic.net/static/nng/glive/icon/b_07.gif'),
    );
    expect(
      emote,
      isNot(const LiveEmote(code: '{:d_48:}', url: 'https://ssl.pstatic.net/static/nng/glive/icon/b_07.gif')),
    );
    expect(emote.hashCode, LiveEmote(code: emote.code, url: emote.url).hashCode);
    expect(emote.toString(), 'LiveEmote({:d_47:}, https://ssl.pstatic.net/static/nng/glive/icon/b_07.gif)');
  });

  group('LiveRetraction', () {
    test('one message, one sender or the whole chat; equal by target', () {
      const one = LiveRetraction.message('m1');
      const sender = LiveRetraction.user('u1');
      const all = LiveRetraction.all();
      expect((one.messageId, one.userId, one.isAll), ('m1', null, false));
      expect((sender.messageId, sender.userId, sender.isAll), (null, 'u1', false));
      expect(all.isAll, isTrue);
      expect(one, const LiveRetraction.message('m1'));
      expect(one, isNot(const LiveRetraction.message('m2')));
      expect(one, isNot(const LiveRetraction.user('m1')));
      expect(one.hashCode, const LiveRetraction.message('m1').hashCode);
      expect([one, sender, all].map((r) => r.toString()), [
        'LiveRetraction.message(m1)',
        'LiveRetraction.user(u1)',
        'LiveRetraction.all()',
      ]);
    });

    test('the new message kinds come after the 3.x ones', () {
      expect(LiveMessageType.values.map((t) => t.name), [
        'chat',
        'gift',
        'online',
        'superChat',
        'retraction',
        'notice',
      ]);
      expect(LiveNoticeKind.values.map((k) => k.name), ['system', 'subscription', 'raid']);
    });
  });

  group('quality labels', () {
    test('Douyin SDK names become Chinese; Chinese labels stay', () {
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: 'ORIGION', id: 'origion'), '原画');
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: 'UHD', id: 'uhd'), '蓝光');
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: 'FULL_HD1', id: 'FULL_HD1'), '蓝光');
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: 'HD', id: 'hd'), '超清');
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: 'SD', id: 'sd'), '高清');
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: 'SD2', id: 'sd2'), '高清');
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: 'LD', id: 'ld'), '标清');
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: 'SD1', id: 'sd1'), '标清');
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: 'MD', id: 'md'), '流畅');
      expect(LiveQualityLabel.normalize(platform: 'douyin', rawLabel: '蓝光', id: 'origin'), '蓝光');
    });

    test('source labels are localized while resolutions stay precise', () {
      expect(LiveQualityLabel.normalize(platform: 'soop', rawLabel: 'original', id: 'original'), '原画');
      expect(LiveQualityLabel.normalize(platform: 'huya', rawLabel: 'source', id: 0), '原画');
      expect(LiveQualityLabel.normalize(platform: 'iptv', rawLabel: 'default'), '默认');
      expect(LiveQualityLabel.normalize(platform: 'twitch', rawLabel: '1080p60 (Source)'), '1080P60（原画）');
      expect(LiveQualityLabel.normalize(platform: 'twitch', rawLabel: '720p'), '720P');
    });

    test('Bilibili qn, resolution, bitrate and id fallbacks are deterministic', () {
      expect(LiveQualityLabel.normalize(platform: 'bilibili', rawLabel: '', id: 10000), '原画');
      expect(LiveQualityLabel.normalize(platform: 'bilibili', rawLabel: '', id: 400), '蓝光');
      expect(LiveQualityLabel.normalize(platform: 'unknown', rawLabel: '', resolution: '1080x1920'), '1080P 高清');
      expect(LiveQualityLabel.normalize(platform: 'unknown', rawLabel: '', bitrate: 2500000), '2.5 Mbps');
      expect(LiveQualityLabel.normalize(platform: 'unknown', rawLabel: '', id: 7), '清晰度 7');
      expect(LiveQualityLabel.normalize(platform: 'unknown', rawLabel: ''), '默认');
    });
  });

  test('asT reads loosely typed JSON', () {
    expect(asT<int>(1), 1);
    expect(asT<int>('1'), isNull);
    expect(asT<String?>(null), isNull);
  });

  test('site errors are typed and say whether retrying can help', () {
    const errors = <SiteError>[
      NotFound('douyu'),
      NeedsLogin('bilibili'),
      RateLimited('kuaishou', retryAfter: Duration(seconds: 3)),
      RiskControl('douyin', cookieSuspect: true),
      RegionBlocked('twitch'),
      StreamUnavailable('huya'),
      UnsupportedLink('x'),
      ApiChanged('yy', 'no data.url'),
      NetworkFailure('cc'),
    ];
    expect(
      [for (final error in errors) error.kind],
      [
        'NotFound',
        'NeedsLogin',
        'RateLimited',
        'RiskControl',
        'RegionBlocked',
        'StreamUnavailable',
        'UnsupportedLink',
        'ApiChanged',
        'NetworkFailure',
      ],
    );
    expect(
      [
        for (final error in errors)
          if (error.isTransient) error.kind,
      ],
      ['RateLimited', 'NetworkFailure'],
    );
    expect(const ApiChanged('yy', 'no data.url').toString(), 'ApiChanged(yy: no data.url)');
  });
}
