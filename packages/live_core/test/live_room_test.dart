import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

/// What 3.x's `LiveRoom.toJson` wrote for a followed IPTV room with every
/// field set (keys and value types as 3.x produced them).
const Map<String, Object?> _v3Json = {
  'roomId': 'cctv1',
  'userId': 'u1',
  'title': 'CCTV-1 综合',
  'nick': 'CCTV',
  'avatar': 'https://img.test/a.png',
  'cover': 'https://img.test/c.png',
  'area': '央视',
  'watching': '0',
  'audienceMetricType': 'unknown',
  'popularity': '',
  'onlineViewers': '',
  'totalViewers': '',
  'followers': '0',
  'platform': 'iptv',
  'tagIds': ['t1', 't2'],
  'liveStatus': 0,
  'isRecord': false,
  'status': true,
  'notice': '',
  'introduction': '',
  'epgId': 'CCTV1',
  'currentProgramme': '新闻联播',
  'currentProgrammeDescription': '每日新闻',
  'catchUpUrl': 'https://tv.test/cctv1.m3u8?playseek=1-2',
  'isCatchUp': true,
  'catchUpStart': 1790000000000,
  'catchUpEnd': 1790001800000,
  'catchUpMode': 'append',
  'catchUpSource': '?playseek={utc:YmdHMS}-{utcend:YmdHMS}',
  'catchUpDays': 7.0,
  'catchUpCorrectionHours': 8.0,
  'httpHeaders': {'referer': 'https://tv.test/', 'user-agent': 'VLC'},
  'lastWatchedAt': 1790002000000,
};

void main() {
  group('3.x JSON', () {
    test('every field 3.x wrote survives a round trip; link is added', () {
      final room = LiveRoom.fromJson(_v3Json);
      final json = room.toJson();
      for (final MapEntry(:key, :value) in _v3Json.entries) {
        expect(json[key], value, reason: key);
      }
      expect(json.keys.toSet().difference(_v3Json.keys.toSet()), {'link'});
      expect(jsonDecode(jsonEncode(json)), isA<Map<String, Object?>>(), reason: 'encodable');
    });

    test('catch-up, headers and history fields are read into their places', () {
      final room = LiveRoom.fromJson(_v3Json);
      expect(room.catchUp.isActive, isTrue);
      expect(room.catchUp.days, 7.0);
      expect(room.httpHeaders, {'referer': 'https://tv.test/', 'user-agent': 'VLC'});
      expect(room.tagIds, ['t1', 't2']);
      expect(room.lastWatchedAt, 1790002000000);
      final live = room.withoutCatchUp();
      expect(live.catchUp.isActive, isFalse);
      expect(live.catchUp.mode, 'append', reason: 'provider settings stay');
      expect(live.catchUp.start, isNull);
    });

    test('sparse and loosely typed records are read like 3.x did', () {
      final room = LiveRoom.fromJson(const {
        'roomId': 7,
        'platform': ' Douyu ',
        'catchUpStart': '17',
        'catchUpDays': 'NaN',
        'httpHeaders': {'Http-User-Agent': 'x', 'bad key': 'y'},
        'tagIds': [1, 'b'],
        'lastWatchedAt': 12.0,
      });
      expect(room.identityKey, 'douyu:7');
      expect(room.catchUp.start, 17);
      expect(room.catchUp.days, isNull, reason: 'not finite');
      expect(room.httpHeaders, {'user-agent': 'x'});
      expect(room.tagIds, ['1', 'b']);
      expect(room.lastWatchedAt, 12);
      expect(room.watching, '0');
      expect(room.followers, '0');
      expect(LiveRoom.fromJson(const {}).platform, 'unknown');
    });
  });

  group('status', () {
    test('without the enum, the old boolean decides', () {
      expect(
        LiveRoom.fromJson(const {'roomId': 'a', 'platform': 'huya', 'status': true}).effectiveLiveStatus,
        LiveStatus.live,
      );
      expect(
        LiveRoom.fromJson(const {'roomId': 'b', 'platform': 'huya', 'status': false}).effectiveLiveStatus,
        LiveStatus.offline,
      );
      expect(LiveRoom.fromJson(const {'roomId': 'c', 'platform': 'huya'}).effectiveLiveStatus, LiveStatus.unknown);
    });

    test('an explicit enum wins over a stale boolean, and the JSON carries no contradiction', () {
      final room = LiveRoom.fromJson(const {'roomId': 'x', 'platform': 'huya', 'status': true, 'liveStatus': 1});
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.isLiveNow, isFalse);
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.toJson()['liveStatus'], LiveStatus.offline.index);
      expect(room.toJson()['status'], isFalse);
    });

    test('unknown and banned stay authoritative', () {
      final pending = LiveRoom.fromJson(const {'roomId': 'p', 'platform': 'huya', 'status': true, 'liveStatus': 3});
      final banned = LiveRoom.fromJson(const {'roomId': 'b', 'platform': 'huya', 'status': true, 'liveStatus': 4});
      expect(pending.isLiveStatusPending, isTrue);
      expect(banned.effectiveLiveStatus, LiveStatus.banned);
      expect(banned.isPlayableNow, isFalse);
    });

    test('a recording room is playable but not live', () {
      final room = LiveRoom.fromJson(const {'roomId': 'r', 'platform': 'kuaishou', 'liveStatus': 0, 'isRecord': true});
      expect(room.effectiveLiveStatus, LiveStatus.replay);
      expect(room.isRecord, isTrue);
      expect(room.isPlayableNow, isTrue);
      expect(room.isLiveNow, isFalse);
      expect(room.toJson()['isRecord'], isTrue);
      expect(room.toJson()['status'], isFalse);
    });

    test('the enum order is the stored format (3.x five, then appended states)', () {
      expect(LiveStatus.values.map((value) => value.name), [
        'live',
        'offline',
        'replay',
        'unknown',
        'banned',
        'carousel',
      ]);
    });

    test('a base site without platform evidence gives an unknown room', () async {
      final room = await _BareSite().getRoomDetail(roomId: 'missing');
      expect(room.identityKey, 'fixture:missing');
      expect(room.isLiveStatusPending, isTrue);
      expect(room.isExplicitlyOfflineNow, isFalse);
      expect(room.audienceValue(preferRealOnline: false, platformEnabled: false), isEmpty);
    });
  });

  group('identity', () {
    test('platform and room id are normalized once; equality is identity', () {
      final room = LiveRoom(platform: ' BILIBILI ', roomId: ' 12345 ');
      expect(room.identityKey, 'bilibili:12345');
      expect(room.hasIdentity(platform: 'Bilibili', roomId: '12345 '), isTrue);
      expect(room.hasIdentity(platform: 'douyu', roomId: '12345'), isFalse);
      expect(room, LiveRoom(platform: 'bilibili', roomId: '12345', title: 'other'));
      expect({room, LiveRoom(platform: 'bilibili', roomId: '12345')}, hasLength(1));
    });

    test('a failed request keeps metadata, makes the state pending and drops the zero default', () {
      final active = LiveRoom(platform: 'bilibili', roomId: '1', title: 't', liveStatus: LiveStatus.replay);
      final fallback = active.pendingAfterError();
      expect(fallback.title, 't');
      expect(fallback.isLiveStatusPending, isTrue);
      expect(fallback.isExplicitlyOfflineNow, isFalse);
      expect(fallback.isRecord, isFalse);
      expect(active.isRecord, isTrue, reason: 'the original is unchanged');
      expect(
        LiveRoom(
          platform: 'bilibili',
          roomId: '1',
        ).pendingAfterError().audienceValue(preferRealOnline: false, platformEnabled: false),
        isEmpty,
      );
    });

    test('fillFromDetail fills only what is empty', () {
      final card = LiveRoom(platform: 'douyu', roomId: '1', nick: 'kept');
      final filled = card.fillFromDetail(LiveRoom(platform: 'douyu', roomId: '1', nick: 'n', avatar: 'a', area: 'x'));
      expect(filled.nick, 'kept');
      expect(filled.avatar, 'a');
      expect(filled.area, 'x');
      expect(card.fillFromDetail(null), same(card));
    });
  });

  group('merge', () {
    test('a sparse refresh keeps local data and omitted fields', () {
      final playback = {'url': 'fixture'};
      final danmaku = {'token': 'fixture'};
      final stored = LiveRoom(
        roomId: '100',
        platform: 'bilibili',
        title: 'old title',
        nick: 'stored nick',
        liveStatus: LiveStatus.replay,
        data: playback,
        danmakuData: danmaku,
        tagIds: const ['local-tag'],
        lastWatchedAt: 123,
      );
      final sparse = LiveRoom(roomId: '100', platform: 'bilibili', title: 'fresh title', tagIds: const ['remote']);
      final merged = stored.mergeFrom(sparse);
      expect(merged.title, 'fresh title');
      expect(merged.nick, 'stored nick');
      expect(merged.effectiveLiveStatus, LiveStatus.replay);
      expect(merged.isRecord, isTrue);
      expect(merged.tagIds, ['local-tag']);
      expect(merged.data, same(playback));
      expect(merged.danmakuData, same(danmaku));
      expect(merged.lastWatchedAt, 123);
    });

    test('an explicit offline snapshot is accepted', () {
      final stored = LiveRoom(roomId: '100', platform: 'bilibili', liveStatus: LiveStatus.replay);
      final merged = stored.mergeFrom(LiveRoom(roomId: '100', platform: 'bilibili', liveStatus: LiveStatus.offline));
      expect(merged.effectiveLiveStatus, LiveStatus.offline);
      expect(merged.isRecord, isFalse);
    });

    test('another identity is ignored; IPTV headers come from the playlist', () {
      final stored = LiveRoom(roomId: '100', platform: 'bilibili', title: 'stored');
      expect(stored.mergeFrom(LiveRoom(roomId: '100', platform: 'huya', title: 'other')), same(stored));
      final channel = LiveRoom(roomId: 'c', platform: 'iptv', httpHeaders: const {'referer': 'old'});
      final merged = channel.mergeFrom(LiveRoom(roomId: 'c', platform: 'iptv', httpHeaders: const {'referer': 'new'}));
      expect(merged.httpHeaders, {'referer': 'new'});
    });

    test('copyWith keeps platform payloads while updating audience', () {
      final playback = {'url': 'fixture'};
      final room = LiveRoom(roomId: '3', platform: 'huya', data: playback, popularity: '500万');
      final updated = room.copyWith(onlineViewers: '3200');
      expect(updated.data, same(playback));
      expect(updated.popularity, '500万');
      expect(updated.onlineViewers, '3200');
    });
  });

  group('audience', () {
    test('platforms map to their usual metric', () {
      expect(LiveRoom(platform: 'bilibili').effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(LiveRoom(platform: 'douyu').effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(LiveRoom(platform: 'huya').effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(LiveRoom(platform: 'kuaishou').effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      expect(LiveRoom(platform: 'twitch').effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      expect(LiveRoom(platform: 'twitch').supportsRealOnlineCount, isTrue);
      expect(LiveRoom(platform: 'soop').supportsRealOnlineCount, isTrue);
      expect(LiveRoom(platform: 'douyin').effectiveAudienceMetricType, AudienceMetricType.totalViewers);
      expect(LiveRoom(platform: 'cc').effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(LiveRoom(platform: 'yy').effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(LiveRoom(platform: 'huya', onlineViewers: '3210').supportsRealOnlineCount, isFalse);
      expect(LiveRoom(platform: 'huya').hasRealOnlineCount, isFalse);
      expect(LiveRoom(platform: 'douyin').supportsRealOnlineCount, isTrue);
      expect(LiveRoom(platform: 'bilibili').supportsRealOnlineCount, isFalse);
    });

    test('heat and concurrent viewers stay separate when choosing a mode', () {
      final room = LiveRoom(
        platform: 'douyin',
        watching: '5600000',
        popularity: '5600000',
        onlineViewers: '18342',
        audienceMetricType: AudienceMetricType.popularity,
      );
      expect(room.audienceValue(preferRealOnline: false, platformEnabled: true), '5600000');
      expect(room.audienceValue(preferRealOnline: true, platformEnabled: true), '18342');
      expect(room.audienceType(preferRealOnline: true, platformEnabled: true), AudienceMetricType.onlineViewers);
      expect(room.audienceSortValue(preferRealOnline: true, platformEnabled: true), 18342);
    });

    test('localized audience numbers parse for ranking', () {
      expect(parseAudienceNumber('5.6万'), 56000);
      expect(parseAudienceNumber('1.2亿'), 120000000);
      expect(parseAudienceNumber('18.3k'), 18300);
      expect(parseAudienceNumber('1.5M'), 1500000);
      expect(parseAudienceNumber('2.4千'), 2400);
      expect(parseAudienceNumber('534，739'), 534739);
      expect(parseAudienceNumber(null), 0);
    });

    test('an explicit zero concurrent count is kept instead of heat', () {
      final room = LiveRoom(platform: 'douyin', popularity: '500万', onlineViewers: '0');
      expect(room.audienceValue(preferRealOnline: true, platformEnabled: true), '0');
      expect(room.audienceType(preferRealOnline: true, platformEnabled: true), AudienceMetricType.onlineViewers);
    });

    test('an unknown metric never shows the zero default', () {
      for (final platform in ['huajiao', 'chzzk', 'bigo', 'tting']) {
        final room = LiveRoom(platform: platform);
        expect(room.audienceValue(preferRealOnline: false, platformEnabled: false), isEmpty, reason: platform);
        expect(room.audienceType(preferRealOnline: false, platformEnabled: false), AudienceMetricType.unknown);
      }
      expect(
        LiveRoom.fromJson(const {'platform': 'chzzk', 'roomId': 'c'})
            .audienceValue(preferRealOnline: false, platformEnabled: false),
        isEmpty,
      );
      expect(
        LiveRoom(platform: 'chzzk', watching: '72').audienceValue(preferRealOnline: false, platformEnabled: false),
        '72',
      );
    });

    test('a pending concurrent value shows empty instead of relabelled heat', () {
      final room = LiveRoom(platform: 'douyin', popularity: '500万');
      expect(room.audienceValue(preferRealOnline: true, platformEnabled: true), isEmpty);
      expect(room.audienceType(preferRealOnline: true, platformEnabled: true), AudienceMetricType.onlineViewers);
      expect(room.audienceSortValue(preferRealOnline: true, platformEnabled: true), 0);
    });

    test('heat of platforms without concurrent counts ranks behind in concurrent mode', () {
      expect(
        LiveRoom(
          platform: 'bilibili',
          popularity: '500万',
        ).audienceSortValue(preferRealOnline: true, platformEnabled: true),
        -1,
      );
      expect(
        LiveRoom(
          platform: 'douyin',
          onlineViewers: '3200',
        ).audienceSortValue(preferRealOnline: true, platformEnabled: true),
        3200,
      );
    });

    test('concurrent ranking separates explicit, pending and native tiers, then identity', () {
      final explicit = LiveRoom(roomId: 'explicit', platform: 'douyin', onlineViewers: '120');
      final pending = LiveRoom(roomId: 'pending', platform: 'soop', popularity: '900万');
      final heat = LiveRoom(roomId: 'heat', platform: 'bilibili', popularity: '900万');
      int compare(LiveRoom a, LiveRoom b) =>
          LiveRoom.compareAudienceRanking(a, b, preferRealOnline: true, platformEnabled: (_) => true);
      expect(([heat, pending, explicit]..sort(compare)).map((room) => room.roomId), ['explicit', 'pending', 'heat']);
      expect(explicit.audienceRankKey(preferRealOnline: true, platformEnabled: true).metricPriority, 3);
      expect(pending.audienceRankKey(preferRealOnline: true, platformEnabled: true).metricPriority, 2);
      expect(heat.audienceRankKey(preferRealOnline: true, platformEnabled: true).metricPriority, 1);
      final equal = [
        LiveRoom(roomId: '2', platform: 'twitch', onlineViewers: '50'),
        LiveRoom(roomId: '1', platform: 'twitch', onlineViewers: '50'),
      ]..sort(compare);
      expect(equal.map((room) => room.roomId), ['1', '2']);
    });

    test('an explicit metric round-trips; older records get the platform default', () {
      final room = LiveRoom.fromJson(const {'roomId': '1', 'platform': 'cc', 'audienceMetricType': 'followers'});
      expect(room.effectiveAudienceMetricType, AudienceMetricType.followers);
      expect(room.toJson()['audienceMetricType'], 'followers');
      expect(
        LiveRoom.fromJson(const {'roomId': '2', 'platform': 'bilibili'}).effectiveAudienceMetricType,
        AudienceMetricType.popularity,
      );
    });

    test('Huya heat stored as concurrent viewers is moved back', () {
      final room = LiveRoom.fromJson(const {
        'roomId': '998',
        'platform': 'HUYA',
        'watching': '5636930',
        'popularity': '5636930',
        'onlineViewers': '3212923',
        'audienceMetricType': 'onlineViewers',
      });
      expect(room.effectivePopularity, '5636930');
      expect(room.effectiveOnlineViewers, isEmpty);
      expect(room.effectiveAudienceMetricType, AudienceMetricType.popularity);
    });

    test('Bilibili list popularity survives a transient 1 from the detail; a plausible heartbeat is accepted', () {
      final list = LiveRoom(
        roomId: '545068',
        platform: 'bilibili',
        watching: '278000',
        popularity: '278000',
        audienceMetricType: AudienceMetricType.popularity,
      );
      final detail = LiveRoom(
        roomId: '545068',
        platform: 'bilibili',
        watching: '1',
        popularity: '1',
        audienceMetricType: AudienceMetricType.popularity,
      );
      final merged = detail.withAudienceFallbackFrom(list);
      expect(merged.watching, '278000');
      expect(merged.effectivePopularity, '278000');
      final heartbeat = list.copyWith(watching: '281500', popularity: '281500').withAudienceFallbackFrom(list);
      expect(heartbeat.effectivePopularity, '281500');
      expect(detail.withAudienceFallbackFrom(LiveRoom(roomId: 'x', platform: 'bilibili')), same(detail));
    });
  });
}

final class _BareSite extends LiveSite {
  @override
  String get id => 'fixture';

  @override
  String get name => 'Fixture';
}
