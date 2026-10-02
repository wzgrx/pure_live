// The room model's upgrade fields (docs/T02/T02g/T02g.2/record.md): start time,
// restriction, carousel, case-insensitive identity and the placeholder rule,
// and that 3.x's JSON still reads as before.
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

/// The keys `toJson` wrote before M2.1: 3.x's keys plus `link`.
const Set<String> _legacyKeys = {
  'roomId',
  'userId',
  'link',
  'title',
  'nick',
  'avatar',
  'cover',
  'area',
  'watching',
  'audienceMetricType',
  'popularity',
  'onlineViewers',
  'totalViewers',
  'followers',
  'platform',
  'tagIds',
  'liveStatus',
  'isRecord',
  'status',
  'notice',
  'introduction',
  'epgId',
  'currentProgramme',
  'currentProgrammeDescription',
  'catchUpUrl',
  'isCatchUp',
  'catchUpStart',
  'catchUpEnd',
  'catchUpMode',
  'catchUpSource',
  'catchUpDays',
  'catchUpCorrectionHours',
  'httpHeaders',
  'lastWatchedAt',
};

/// 3.x's `LiveRoom._liveStatusFromJson` (legacy `live_room.dart:609-620`)
/// over its five-value enum, to show what 3.x makes of a v4 record.
String _v3StatusName(Map<String, Object?> json) {
  const v3 = ['live', 'offline', 'replay', 'unknown', 'banned'];
  final raw = json['liveStatus'];
  final index = raw is int ? raw : int.tryParse('$raw');
  if (index != null && index >= 0 && index < v3.length) return v3[index];
  if (json['isRecord'] == true) return 'replay';
  return switch (json['status']) {
    true => 'live',
    false => 'offline',
    _ => 'unknown',
  };
}

LiveRoom _room({
  String platform = 'bilibili',
  String roomId = '1',
  LiveStatus? status,
  DateTime? startedAt,
  LiveRestriction? restriction,
}) => LiveRoom(platform: platform, roomId: roomId, liveStatus: status, startedAt: startedAt, restriction: restriction);

void main() {
  group('start time', () {
    final start = DateTime.utc(2026, 9, 28, 12, 34, 56, 789);

    test('is written as ISO 8601 UTC under a new key and read back', () {
      final json = _room(status: LiveStatus.live, startedAt: start).toJson();
      expect(json['startedAt'], '2026-09-28T12:34:56.789Z');
      final decoded = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      final back = LiveRoom.fromJson(decoded);
      expect(back.startedAt, start);
      expect(back.startedAt!.isUtc, isTrue);
      expect(back.toJson()['startedAt'], json['startedAt']);
    });

    test('a local time is stored as the same instant in UTC', () {
      final local = DateTime(2026, 9, 28, 20);
      final room = _room(startedAt: local);
      expect(room.startedAt!.isUtc, isTrue);
      expect(room.startedAt!.isAtSameMomentAs(local), isTrue);
    });

    test('reading accepts epoch milliseconds and ISO texts; anything else is null', () {
      DateTime? read(Object? value) =>
          LiveRoom.fromJson({'roomId': 'r', 'platform': 'douyu', 'startedAt': value}).startedAt;
      final millis = start.millisecondsSinceEpoch;
      expect(read(millis), start);
      expect(read(millis.toDouble()), start);
      expect(read(' $millis '), start);
      expect(read('2026-09-28T21:34:56.789+09:00'), start, reason: 'an offset is honoured');
      expect(read('2026-09-28T12:34:56.789'), start, reason: 'no offset means UTC, as written');
      expect(read('2026-09-28 12:34:56.789Z'), start);
      for (final bad in <Object?>[
        null,
        '',
        'yesterday',
        0,
        -5,
        '0',
        true,
        1e30,
        <String, Object?>{},
        '1969-12-31T00:00:00Z',
      ]) {
        expect(read(bad), isNull, reason: '$bad');
      }
    });

    test('a room without it writes no key', () {
      expect(_room(status: LiveStatus.live).toJson().containsKey('startedAt'), isFalse);
    });
  });

  group('restriction', () {
    test('the names are the stored format', () {
      expect(LiveRestriction.values.map((value) => value.name), [
        'none',
        'needsLogin',
        'paid',
        'subscribersOnly',
        'private',
        'appOnly',
        'regionBlocked',
        'password',
        'adult',
        'unplayable',
      ]);
    });

    test('every kind round-trips by name, none included', () {
      for (final kind in LiveRestriction.values) {
        final json = _room(status: LiveStatus.live, restriction: kind).toJson();
        expect(json['restriction'], kind.name);
        final back = LiveRoom.fromJson(jsonDecode(jsonEncode(json)) as Map<String, Object?>);
        expect(back.restriction, kind, reason: kind.name);
      }
    });

    test('an unknown name reads as none; an absent one as not given', () {
      LiveRoom read(Object? value) => LiveRoom.fromJson({'roomId': 'r', 'platform': 'tiktok', 'restriction': value});
      expect(read('ticketedLater').restriction, LiveRestriction.none);
      expect(read('PAID').restriction, LiveRestriction.none, reason: 'names are exact');
      expect(read(3).restriction, LiveRestriction.none);
      expect(read(null).restriction, isNull);
      expect(LiveRoom.fromJson(const {'roomId': 'r', 'platform': 'tiktok'}).restriction, isNull);
      expect(LiveRestriction.fromName('paid'), LiveRestriction.paid);
    });

    test('not given and no restriction differ in the model and the JSON, but show alike', () {
      final unknown = _room(status: LiveStatus.live);
      final none = _room(status: LiveStatus.live, restriction: LiveRestriction.none);
      expect(unknown.restriction, isNull);
      expect(none.restriction, LiveRestriction.none);
      expect(unknown.toJson().containsKey('restriction'), isFalse);
      expect(none.toJson()['restriction'], 'none');
      expect([unknown.effectiveRestriction, none.effectiveRestriction], everyElement(LiveRestriction.none));
      expect([unknown.isRestricted, none.isRestricted], everyElement(isFalse));
      expect(_room(restriction: LiveRestriction.paid).isRestricted, isTrue);
    });

    test('a restricted live room stays live and playable', () {
      final room = _room(status: LiveStatus.live, restriction: LiveRestriction.paid);
      expect(room.isLiveNow, isTrue);
      expect(room.isPlayableNow, isTrue);
      expect(room.followGroup, FollowGroup.live);
      expect(room.toJson()['status'], isTrue);
    });
  });

  group('carousel', () {
    test('is appended as index 5; the 3.x indexes keep their meaning', () {
      expect(LiveStatus.carousel.index, 5);
      expect([for (final status in LiveStatus.values.take(5)) status.index], [0, 1, 2, 3, 4]);
      final room = LiveRoom.fromJson(const {'roomId': '21', 'platform': 'bilibili', 'liveStatus': 5, 'status': false});
      expect(room.effectiveLiveStatus, LiveStatus.carousel);
      expect(room.toJson(), containsPair('liveStatus', 5));
      expect(room.toJson(), containsPair('status', false));
      expect(room.toJson(), containsPair('isRecord', false));
    });

    test('groups with offline and is not playable', () {
      final room = _room(status: LiveStatus.carousel);
      expect(room.isLiveNow, isFalse);
      expect(room.isPlayableNow, isFalse);
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.isLiveStatusPending, isFalse);
      expect(room.isRecord, isFalse);
      expect(room.followGroup, FollowGroup.offline);
    });

    test('3.x reads a carousel record as offline', () {
      expect(_v3StatusName(_room(status: LiveStatus.carousel).toJson()), 'offline');
      for (final status in LiveStatus.values.take(5)) {
        expect(_v3StatusName(_room(status: status).toJson()), status.name, reason: 'unchanged for 3.x states');
      }
    });

    test('follow groups: live, playable replay, everything else offline', () {
      FollowGroup group(LiveStatus? status, [LiveRestriction? restriction]) =>
          _room(status: status, restriction: restriction).followGroup;
      expect(group(LiveStatus.live), FollowGroup.live);
      expect(
        group(LiveStatus.live, LiveRestriction.unplayable),
        FollowGroup.live,
        reason: 'shown live, explained on play',
      );
      expect(group(LiveStatus.replay), FollowGroup.replay);
      expect(group(LiveStatus.replay, LiveRestriction.none), FollowGroup.replay);
      expect(group(LiveStatus.replay, LiveRestriction.unplayable), FollowGroup.offline);
      for (final status in [LiveStatus.offline, LiveStatus.unknown, LiveStatus.banned, LiveStatus.carousel, null]) {
        expect(group(status), FollowGroup.offline, reason: '$status');
      }
    });

    test('an unplayable replay is still a replay for playback and 3.x', () {
      final room = _room(status: LiveStatus.replay, restriction: LiveRestriction.unplayable);
      expect(room.isPlayableNow, isTrue, reason: 'the rule is unchanged; playback explains the restriction');
      expect(room.isRecord, isTrue);
      expect(_v3StatusName(room.toJson()), 'replay');
    });
  });

  group('identity', () {
    test('case is ignored only on the listed platforms', () {
      expect(SiteIds.caseInsensitiveRoomIds, {
        'twitch',
        'soop',
        'picarto',
        'twitcasting',
        'tiktok',
        'pandalive',
        'douyu',
        'kuaishou',
        'bigo',
        'kick',
      });
      expect(SiteIds.supported.toSet().containsAll(SiteIds.caseInsensitiveRoomIds), isTrue);
      for (final platform in SiteIds.supported) {
        final upper = _room(platform: platform, roomId: 'TheBaker');
        final lower = _room(platform: platform, roomId: 'thebaker');
        final folded = SiteIds.caseInsensitiveRoomIds.contains(platform);
        expect(upper.hasSameIdentity(lower), folded, reason: platform);
        expect(upper == lower, folded, reason: platform);
        expect({upper, lower}, hasLength(folded ? 1 : 2), reason: platform);
        expect(
          upper.hasIdentity(platform: platform.toUpperCase(), roomId: ' THEBAKER '),
          folded,
          reason: platform,
        );
        expect(upper.roomId, 'TheBaker', reason: 'the stored spelling stays');
      }
    });

    test('a YouTube video id stays case-sensitive', () {
      final video = _room(platform: 'youtube', roomId: 'dQw4w9WgXcQ');
      expect(video.hasSameIdentity(_room(platform: 'youtube', roomId: 'dqw4w9wgxcq')), isFalse);
      expect(video.identityKey, 'youtube:dQw4w9WgXcQ');
      expect(video.hasIdentity(platform: 'YouTube', roomId: 'dQw4w9WgXcQ'), isTrue);
    });

    test('the key folds the room id on case-insensitive platforms, whatever the platform spelling', () {
      expect(LiveRoom.identityKeyFor(platform: ' Picarto ', roomId: ' TheBaker '), 'picarto:thebaker');
      expect(LiveRoom.identityKeyFor(platform: 'TWITCH', roomId: 'Shroud'), 'twitch:shroud');
      expect(LiveRoom.identityKeyFor(platform: 'bigo', roomId: 'Qashia305'), 'bigo:qashia305');
      expect(LiveRoom.identityKeyFor(platform: 'huya', roomId: 'Qashia305'), 'huya:Qashia305');
      expect(SiteIds.ignoresRoomIdCase(' SOOP '), isTrue);
      expect(SiteIds.ignoresRoomIdCase('youtube'), isFalse);
      expect(_room(platform: 'picarto', roomId: 'TheBaker').toString(), contains('picarto:TheBaker'));
    });

    test('a refresh in another case merges into the follow; the follow keeps its spelling', () {
      final stored = LiveRoom(platform: 'picarto', roomId: 'TheBaker', title: 'old', tagIds: const ['t']);
      final merged = stored.mergeFrom(LiveRoom(platform: 'picarto', roomId: 'thebaker', title: 'new'));
      expect(merged.title, 'new');
      expect(merged.roomId, 'TheBaker');
      expect(merged.tagIds, ['t']);
      final video = LiveRoom(platform: 'youtube', roomId: 'dQw4w9WgXcQ', title: 'old');
      expect(video.mergeFrom(LiveRoom(platform: 'youtube', roomId: 'dqw4w9wgxcq', title: 'new')), same(video));
    });
  });

  group('merge', () {
    final start = DateTime.utc(2026, 9, 28, 10);
    final later = DateTime.utc(2026, 9, 28, 11);

    test('an omitted start time keeps the stored one within the same broadcast', () {
      final stored = _room(status: LiveStatus.live, startedAt: start);
      expect(stored.mergeFrom(_room()).startedAt, start, reason: 'state not given');
      expect(stored.mergeFrom(_room(status: LiveStatus.live)).startedAt, start);
      expect(stored.mergeFrom(_room(status: LiveStatus.unknown)).startedAt, start);
      expect(
        stored.mergeFrom(_room(status: LiveStatus.live, startedAt: later)).startedAt,
        later,
        reason: 'new wins',
      );
    });

    test('a changed state drops the last broadcast start time', () {
      final stored = _room(status: LiveStatus.live, startedAt: start);
      final ended = stored.mergeFrom(_room(status: LiveStatus.offline));
      expect(ended.startedAt, isNull);
      expect(ended.mergeFrom(_room(status: LiveStatus.live)).startedAt, isNull, reason: 'a later broadcast');
      expect(stored.mergeFrom(_room(status: LiveStatus.carousel)).startedAt, isNull);
      expect(
        _room(status: LiveStatus.replay, startedAt: start).mergeFrom(_room(status: LiveStatus.live)).startedAt,
        isNull,
      );
    });

    test('after a failed request the next answer of the same broadcast keeps the start time', () {
      final pending = _room(status: LiveStatus.live, startedAt: start).pendingAfterError();
      expect(pending.startedAt, start);
      expect(pending.mergeFrom(_room(status: LiveStatus.live)).startedAt, start);
    });

    test('a given restriction wins, none included; an omitted one keeps the stored one', () {
      final paid = _room(status: LiveStatus.live, restriction: LiveRestriction.paid);
      expect(paid.mergeFrom(_room()).restriction, LiveRestriction.paid, reason: 'a light refresh says nothing');
      expect(paid.mergeFrom(_room(status: LiveStatus.live)).restriction, LiveRestriction.paid);
      expect(
        paid.mergeFrom(_room(status: LiveStatus.live, restriction: LiveRestriction.none)).restriction,
        LiveRestriction.none,
      );
      expect(
        _room(
          status: LiveStatus.live,
          restriction: LiveRestriction.none,
        ).mergeFrom(_room(restriction: LiveRestriction.private)).restriction,
        LiveRestriction.private,
      );
      expect(paid.pendingAfterError().restriction, LiveRestriction.paid);
      expect(paid.pendingAfterError().mergeFrom(_room(status: LiveStatus.live)).restriction, LiveRestriction.paid);
    });

    test('a changed state makes an omitted restriction not known', () {
      final unplayable = _room(status: LiveStatus.replay, restriction: LiveRestriction.unplayable);
      final live = unplayable.mergeFrom(_room(status: LiveStatus.live));
      expect(live.restriction, isNull);
      expect(live.followGroup, FollowGroup.live);
      final paid = _room(status: LiveStatus.live, restriction: LiveRestriction.paid);
      expect(paid.mergeFrom(_room(status: LiveStatus.offline)).restriction, isNull);
      expect(
        paid.mergeFrom(_room(status: LiveStatus.offline, restriction: LiveRestriction.none)).restriction,
        LiveRestriction.none,
      );
    });

    test('copyWith carries and replaces both fields', () {
      final room = _room(status: LiveStatus.live, startedAt: start, restriction: LiveRestriction.adult);
      expect(room.copyWith(title: 't').startedAt, start);
      expect(room.copyWith(title: 't').restriction, LiveRestriction.adult);
      expect(room.copyWith(startedAt: later, restriction: LiveRestriction.none).startedAt, later);
      expect(room.copyWith(restriction: LiveRestriction.none).restriction, LiveRestriction.none);
    });
  });

  group('placeholders', () {
    test('an empty name, title or cover keeps what the follow stored', () {
      final stored = LiveRoom(platform: 'jdlive', roomId: '9', nick: 'Shop', title: 'Sale', cover: 'https://c/1.jpg');
      final merged = stored.mergeFrom(
        LiveRoom(platform: 'jdlive', roomId: '9', nick: ' ', liveStatus: LiveStatus.live),
      );
      expect((merged.nick, merged.title, merged.cover), ('Shop', 'Sale', 'https://c/1.jpg'));
    });

    test('the UI shows the platform name for an empty streamer name', () {
      expect(LiveRoom(platform: 'jdlive').displayNick('京东直播'), '京东直播');
      expect(LiveRoom(platform: 'jdlive', nick: '  ').displayNick('京东直播'), '京东直播');
      expect(LiveRoom(platform: 'jdlive', nick: ' Shop ').displayNick('京东直播'), 'Shop');
      expect(LiveRoom(platform: 'jdlive', nick: '  ').hasNick, isFalse);
      expect(LiveRoom(platform: 'jdlive', nick: 'Shop').hasNick, isTrue);
    });
  });

  group('3.x JSON in the fixtures', () {
    // Every room 3.x's parsers produced for the recorded samples
    // (`fixtures/*/*/expected.json`), as 3.x's `toJson` wrote it.
    final rooms = <(String, Map<String, Object?>)>[];
    void collect(Object? value, String source) {
      if (value is Map<String, Object?>) {
        if (value.containsKey('roomId') && value.containsKey('platform') && value.containsKey('liveStatus')) {
          rooms.add((source, value));
        }
        for (final child in value.values) {
          collect(child, source);
        }
      } else if (value is List<Object?>) {
        for (final child in value) {
          collect(child, source);
        }
      }
    }

    for (final file in Directory('../../fixtures').listSync(recursive: true).whereType<File>()) {
      if (file.uri.pathSegments.last == 'expected.json') collect(jsonDecode(file.readAsStringSync()), file.path);
    }

    test('cover every platform', () {
      expect(rooms.length, greaterThan(1000));
      final platforms = {for (final (_, json) in rooms) '${json['platform']}'.toLowerCase()};
      // Kick has no 3.x output: 3.2.11 retired it before the parsers were
      // recorded (M4.34).
      expect(platforms, containsAll(SiteIds.supported.where((id) => id != SiteIds.iptv && id != SiteIds.kick)));
    });

    test('read without the new fields and write the same keys and state as before', () {
      for (final (source, json) in rooms) {
        final room = LiveRoom.fromJson(json);
        final reason = '$source ${json['platform']}:${json['roomId']}';
        expect(room.startedAt, isNull, reason: reason);
        expect(room.restriction, isNull, reason: reason);
        expect(room.isRestricted, isFalse, reason: reason);
        final written = room.toJson();
        expect(written.keys.toSet(), _legacyKeys, reason: reason);
        expect(written['liveStatus'], json['liveStatus'], reason: reason);
        expect(written['status'], json['status'], reason: reason);
        final v3Group = switch (_v3StatusName(json)) {
          'live' => FollowGroup.live,
          'replay' => FollowGroup.replay,
          _ => FollowGroup.offline,
        };
        expect(room.followGroup, v3Group, reason: reason);
        expect(LiveRoom.fromJson(written).toJson(), written, reason: reason);
      }
    });
  });
}
