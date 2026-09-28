// LiveMe parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/liveme/legacy_expected.dart from 3.x's LiveMeApi, LiveMeLink,
// LiveMeSigner and LiveMeSite). Every intended difference is listed with its
// reason (M4.21's differences, and the M4.U upgrade numbers 21-1 to 21-8);
// everything else must match. The synthetic cases port 3.x's
// liveme_directory_test.dart and pin the rest of the parsing rules.
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('liveme', name);

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences). 3.x wrote null where
/// the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

/// Intended differences on every room: 3.x also wrote its media headers into
/// the room (`httpHeaders`, read back only by the IPTV branch of its header
/// resolver); they now travel with each play line. The `notice` is 3.x's
/// chat note said for viewers (M4.U, the unified rule on explanatory text).
const _changed = {'httpHeaders', 'notice'};

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The outcome of a counted legacy call (`{value, requests}`).
Object? _value(String name, String key) => (_legacy(name)[key] as Map<String, dynamic>)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

const _shortId = '209683072';
const _userId = '932385543319330816';
const _videoId = '17904580585651396476';
const _offlineShortId = '17709377';
const _offlineUserId = '560875115161059328';

/// `vtime` of the live sample's broadcast.
final _liveStart = DateTime.utc(2026, 9, 26, 21, 31, 2);

LiveMeProfile _liveProfile() => LiveMeApi.profile(_sample('S04-profile-live').body, userId: _userId);

LiveMeSnapshot _liveVideo({bool media = true}) =>
    LiveMeApi.video(_sample('S05-query-live').body, videoId: _videoId, shortId: _shortId, media: media);

/// Room entry of the live sample, as the site builds it.
LiveRoom _liveRoom({bool media = true}) {
  final snapshot = LiveMeApi.withProfile(_liveVideo(media: media), _liveProfile());
  return LiveMeApi.room(snapshot, data: media ? LiveMeApi.roomData(snapshot) : null);
}

LiveMeRoomData _liveData() => _liveRoom().data! as LiveMeRoomData;

Map<String, dynamic> _video([Map<String, Object?> changes = const {}]) => {
  'ushortid': '12345678',
  'userid': '1234567890123456789',
  'vid': _videoId,
  'uname': 'Anchor',
  'title': '',
  'online': 1,
  'status': 0,
  'roomstate': 0,
  'playnumber': 120,
  'countryCode': 'US',
  'vtime': '1790458262',
  ...changes,
};

String _envelope(Object? data, {Object status = '200', String message = ''}) =>
    jsonEncode({'status': status, 'msg': message, 'data': data});

String _featured(List<Object?> rows, {Object nextPage = 0}) => _envelope({'video_info': rows, 'next_page': nextPage});

String _search(List<Object?> rows) => _envelope({'data_info': rows});

Map<String, Object?> _row([Map<String, Object?> changes = const {}]) => {
  'short_id': '12345678',
  'user_id': '1234567890123456789',
  'nickname': 'Row',
  'face': 'https://esx.esxscloud.com/face.jpg',
  'is_live': '1',
  'project': 'liveme',
  'countryCode': 'us',
  'fans_num': '12',
  ...changes,
};

String _query(Map<String, Object?> video, {Map<String, Object?>? user}) =>
    _envelope({'video_info': video, 'user_info': ?user});

LiveMeSnapshot _snapshot(Map<String, Object?> changes, {bool media = true, Map<String, Object?>? user}) =>
    LiveMeApi.video(
      _query(_video(changes), user: user),
      videoId: _videoId,
      media: media,
    );

/// The paid label as the site sends it: JSON text (the shape of the labels
/// in S01, with the text the web client checks).
const _paidLabel = '{"lid":"8","img":"","color":"#7F000000","text":"Paid broadcast","type":"1"}';

void main() {
  group('S01 featured list', () {
    for (final (name, page, placeholders) in [('S01-featurelist-p1', 1, 10), ('S01-featurelist-p2', 2, 11)]) {
      test('$name matches 3.x but for the default titles; start and restriction added', () {
        final result = LiveMeApi.featuredPage(_sample(name).body, page: page);
        final legacy = _value(name, 'getDirectoryPage')! as Map<String, dynamic>;
        expect((result.page, result.hasMore), (legacy['page'], legacy['hasMore']));
        final rooms = _maps(legacy['rooms']);
        expect(result.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
        var defaults = 0;
        for (final (index, room) in result.rooms.indexed) {
          final placeholder = LiveMeApi.defaultTitles.contains(rooms[index]['title']);
          _expectParity(
            _projection(room),
            rooms[index],
            // Placeholder rule: the app's default title is no title, so the
            // card is named by the anchor, as 3.x named an untitled one.
            changed: {..._changed, if (placeholder) 'title'},
            reason: '$name[$index]',
          );
          if (placeholder) {
            defaults++;
            expect(room.title, room.nick, reason: '$name[$index]');
          }
          expect(room.data, isNull, reason: 'list cards carry no stream data');
          expect(room.isLiveNow, isTrue);
          expect(room.restriction, LiveRestriction.none, reason: 'unified rule: the card says it');
          expect(room.startedAt, isNotNull, reason: 'unified rule: vtime');
        }
        expect(defaults, placeholders);
        expect(_value(name, 'getRecommendRooms'), legacy['rooms'], reason: 'the same page');
      });
    }

    test("the room is the short id, 3.x's link and audience; vtime is the start", () {
      final first = LiveMeApi.featuredPage(_sample('S01-featurelist-p1').body, page: 1).rooms.first;
      expect((first.roomId, first.userId), (_shortId, _userId));
      expect(first.link, 'https://www.liveme.com/livehot/streaming/$_shortId');
      expect(jsonEncode(first.toJson()), isNot(contains(_videoId)), reason: 'the broadcast is no identity');
      expect(
        (first.popularity, first.watching, first.onlineViewers, first.totalViewers),
        ('882', '882', '202', '8670'),
      );
      expect(first.audienceMetricType, AudienceMetricType.popularity);
      expect(first.notice, LiveMeApi.chatNotice);
      expect(
        _maps((_value('S01-featurelist-p1', 'getDirectoryPage')! as Map)['rooms']).first['notice'],
        'LiveMe 远端聊天尚待接入；热度、当前观看和累计观看分别展示。',
        reason: "3.x's developer-style note, now said for viewers",
      );
      expect(LiveMeApi.chatNotice, isNot(contains('接入')));
      expect(first.httpHeaders, isEmpty);
      expect(first.title, '.', reason: "the anchor's own title stays");
      expect(first.startedAt, _liveStart);
      expect(first.toJson()['startedAt'], '2026-09-26T21:31:02.000Z');
      final legacy = _legacy('S01-featurelist-p1');
      expect(legacy['directoryNoticeKey'], 'liveme_directory_scope');
      expect(
        (legacy['getPlayQualites(card)']! as Map)['message'],
        'LiveMe identity',
        reason: '3.x could not give a list card qualities; the site now asks for its broadcast',
      );
    });

    test('a card without a short id is skipped; a malformed one only drops itself (unified rule)', () {
      final union = _video({'ushortid': null, 'union_room_id': 'fixture'})..remove('ushortid');
      final page = LiveMeApi.featuredPage(
        _featured([
          _video(),
          union,
          _video({'ushortid': '23456789', 'userid': '2234567890123456789'}),
        ]),
        page: 1,
      );
      expect(page.rooms.map((room) => room.roomId), ['12345678', '23456789']);
      expect(page.hasMore, isFalse);
      final bad = [
        _video({'ushortid': '12'}),
        _video({'ushortid': '0123456'}),
        _video({'userid': '12'}),
        _video({'uname': '', 'title': 'x'}),
        _video({'title': 7}),
        _video({'playnumber': -1}),
        _video({'playnumber': '1.5'}),
        'not an object',
      ];
      final mixed = LiveMeApi.featuredPage(
        _featured([
          ...bad,
          _video({'ushortid': '34567890'}),
        ], nextPage: '1'),
        page: 2,
      );
      expect(mixed.rooms.map((room) => room.roomId), ['34567890'], reason: '3.x failed the page on any bad card');
      expect(mixed.hasMore, isTrue);
      for (final row in bad) {
        expect(
          () => LiveMeApi.featuredPage(_featured([row, union]), page: 1),
          throwsA(isA<ApiChanged>()),
          reason: 'nothing usable: $row',
        );
      }
      expect(LiveMeApi.featuredPage(_featured([union]), page: 1).rooms, isEmpty, reason: 'nothing broken either');
      expect(
        () => LiveMeApi.featuredPage(_featured(List.filled(101, _video())), page: 1),
        throwsA(isA<ApiChanged>()),
        reason: "3.x's limit of 100 rows",
      );
      expect(
        () => LiveMeApi.featuredPage(_envelope({'video_info': <String, Object?>{}}), page: 1),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('21-1, 21-5: private and paid broadcasts are listed live and marked; the label is JSON text', () {
      final page = LiveMeApi.featuredPage(
        _featured([
          _video(),
          _video({'userid': '2234567890123456789'}),
          _video({'ushortid': '20000', 'ispvt': '1'}),
          _video({'ushortid': '20001', 'livebptype': '7'}),
          _video({
            'ushortid': '20002',
            'hot_label_v2': {'text': 'Paid Broadcast'},
          }),
          _video({'ushortid': '20003', 'hot_label_v2': _paidLabel}),
          _video({'ushortid': '20004', 'hot_label_v2': '{"lid":"8","text":"Multi-beam","type":"1"}'}),
        ], nextPage: '1'),
        page: 3,
      );
      expect(
        [for (final room in page.rooms) (room.roomId, room.effectiveLiveStatus, room.restriction)],
        [
          ('12345678', LiveStatus.live, LiveRestriction.none),
          ('20000', LiveStatus.live, LiveRestriction.private),
          ('20001', LiveStatus.live, LiveRestriction.paid),
          ('20002', LiveStatus.live, LiveRestriction.paid),
          ('20003', LiveStatus.live, LiveRestriction.paid),
          ('20004', LiveStatus.live, LiveRestriction.none),
        ],
        reason: '3.x left them out and never read the label as the site sends it; the discovery page hides them (M13)',
      );
      expect(page.rooms.where((room) => room.isRestricted).map((room) => room.isLiveNow), everyElement(isTrue));
      expect((page.page, page.hasMore), (3, true));
    });

    test("21-1: the paid label is read by the web client's rule", () {
      for (final label in [
        _paidLabel,
        ' {"text":" PAID BROADCAST "} ',
        {'text': 'paid broadcast'},
      ]) {
        expect(LiveMeApi.isPaidLabel(label), isTrue, reason: '$label');
      }
      final samples = <String>{
        for (final name in ['S01-featurelist-p1', 'S01-featurelist-p2'])
          for (final row in ((jsonDecode(_sample(name).body) as Map)['data'] as Map)['video_info'] as List)
            '${(row as Map)['hot_label_v2']}',
      };
      expect(samples.length, greaterThan(2), reason: 'H2H, Multi-beam and no label');
      for (final label in [...samples, '{"text":', '[]', '{"text":7}', 'Paid broadcast', null, 7]) {
        expect(LiveMeApi.isPaidLabel(label), isFalse, reason: '$label');
      }
      expect(LiveMeApi.restrictionOf(_video({'ispvt': '1', 'livebptype': '7'})), LiveRestriction.private);
      expect(LiveMeApi.restrictionOf(_video({'livebptype': '4'})), LiveRestriction.none);
    });

    test('placeholder rule: the app default titles name the card by the anchor, other titles stay', () {
      for (final title in LiveMeApi.defaultTitles) {
        expect(_snapshot({'title': ' $title '}).title, 'Anchor', reason: title);
      }
      for (final title in ['Click for fun!!', 'click for fun!', 'Click for fun and more!', '.']) {
        expect(_snapshot({'title': title}).title, title, reason: title);
      }
      expect(LiveMeApi.defaultTitles, hasLength(5));
    });
  });

  group('S02 search', () {
    for (final name in ['S02-search-p1', 'S02-search-p2', 'S02-search-empty']) {
      test('$name matches 3.x but for the union projects (21-4)', () {
        final rooms = LiveMeApi.searchPage(_sample(name).body);
        final legacy = _maps(_value(name, 'searchRooms'));
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          final union = legacy[index]['liveStatus'] == LiveStatus.unknown.index;
          _expectParity(
            _projection(room),
            legacy[index],
            // 21-4: a union project's is_live 0 is offline; 3.x said unknown.
            changed: {..._changed, if (union) 'liveStatus'},
            reason: '$name[$index]',
          );
          expect(room.effectiveLiveStatus, LiveStatus.offline, reason: '$name[$index]');
          expect((room.restriction, room.startedAt), (null, null), reason: 'a search row does not say');
        }
        // 3.x's `hasMore` (rows >= pageSize) was false for every page of 20
        // but its site never passed it on: the search page kept paging
        // while pages brought new rooms.
        expect(_legacy(name)['LiveMeApi.search.hasMore'], isFalse);
      });
    }

    test('the site answers 20 a page and pages do not overlap; 19 union anchors', () {
      final first = LiveMeApi.searchPage(_sample('S02-search-p1').body);
      final second = LiveMeApi.searchPage(_sample('S02-search-p2').body);
      expect((first.length, second.length), (20, 20));
      expect(first.map((room) => room.roomId).toSet().intersection(second.map((room) => room.roomId).toSet()), isEmpty);
      final legacy = [
        ..._maps(_value('S02-search-p1', 'searchRooms')),
        ..._maps(_value('S02-search-p2', 'searchRooms')),
      ];
      expect(legacy.where((room) => room['liveStatus'] == LiveStatus.unknown.index), hasLength(19));
    });

    test('21-4 states: is_live 1 live, 0 offline for every project; else unknown', () {
      final rooms = LiveMeApi.searchPage(
        _search([
          _row(),
          _row({'short_id': '20000', 'is_live': '0'}),
          _row({'short_id': '20001', 'is_live': 0, 'project': 'emolm'}),
          _row({'short_id': '20002', 'is_live': null, 'project': 'LiveMe'}),
          _row({'short_id': '20003', 'is_live': '2'}),
          _row({'short_id': '20004', 'is_live': '0', 'project': 7}),
        ]),
      );
      expect(rooms.map((room) => room.effectiveLiveStatus), [
        LiveStatus.live,
        LiveStatus.offline,
        LiveStatus.offline,
        LiveStatus.unknown,
        LiveStatus.unknown,
        LiveStatus.offline,
      ]);
      final first = rooms.first;
      expect((first.title, first.nick, first.area, first.followers, first.cover), ('Row', 'Row', 'US', '12', ''));
      expect(first.audienceMetricType, AudienceMetricType.onlineViewers, reason: '3.x: no heat, so viewers');
      expect((first.watching, first.popularity, first.onlineViewers), ('', '', ''));
    });

    test('rows: uname when no nickname, follower_count when no fans_num, each room once (3.x)', () {
      final rooms = LiveMeApi.searchPage(
        _search([
          _row({'nickname': ' ', 'uname': 'Other', 'fans_num': null, 'follower_count': '5'}),
          _row({'nickname': 'Again'}),
        ]),
      );
      expect(rooms.single.nick, 'Other');
      expect(rooms.single.followers, '5');
    });

    test('a malformed row only drops itself; a page of malformed rows is ApiChanged (unified rule)', () {
      final bad = [
        _row({'short_id': '1234'}),
        _row({'user_id': null}),
        _row({'nickname': null, 'uname': ''}),
        _row({'fans_num': '-3'}),
        'not an object',
      ];
      final rooms = LiveMeApi.searchPage(
        _search([
          ...bad,
          _row({'short_id': '23456789'}),
        ]),
      );
      expect(rooms.map((room) => room.roomId), ['23456789'], reason: '3.x failed the page on any bad row');
      for (final row in bad) {
        expect(() => LiveMeApi.searchPage(_search([row])), throwsA(isA<ApiChanged>()), reason: '$row');
      }
      final again = LiveMeApi.searchPage(
        _search([
          _row({'fans_num': '-3'}),
          _row({'nickname': 'Good'}),
        ]),
      );
      expect(again.single.nick, 'Good', reason: 'a bad first row does not hide a good second one');
    });
  });

  group('S03–S05 rooms', () {
    test('S03 mapping: the user and the broadcast; none when not broadcasting', () {
      expect(LiveMeApi.mapping(_sample('S03-mapping-live').body), (userId: _userId, videoId: _videoId));
      expect(LiveMeApi.mapping(_sample('S03-mapping-offline').body), (userId: _offlineUserId, videoId: ''));
      expect(() => LiveMeApi.mapping(_sample('S03-mapping-notfound').body), throwsA(isA<NotFound>()));
      expect(
        (_value('S03-mapping-notfound', 'getRoomDetail')! as Map)['message'],
        'LiveMe missing',
        reason: '3.x: missing too',
      );
      for (final data in [
        {'uid': '12', 'vid': ''},
        {'uid': _userId, 'vid': '99'},
        {'uid': _userId, 'vid': 1790458058565139},
        {'vid': ''},
      ]) {
        expect(() => LiveMeApi.mapping(_envelope(data)), throwsA(isA<ApiChanged>()), reason: '$data');
      }
    });

    test('S04 profile: the anchor asked for; "user not exist" is NotFound (3.x: service)', () {
      final profile = _liveProfile();
      expect(
        (profile.shortId, profile.userId, profile.followers, profile.countryCode),
        (_shortId, _userId, 33933, 'US'),
      );
      expect(profile.avatar, contains('/540x540/'), reason: 'big_face first');
      expect(profile.bio, startsWith('NVIPSupport'));
      expect(
        () => LiveMeApi.profile(_sample('S04-profile-live').body, userId: _offlineUserId),
        throwsA(isA<ApiChanged>()),
      );
      expect(
        () => LiveMeApi.profile(_sample('S04-profile-notfound').body, userId: '1000000000000000001'),
        throwsA(isA<NotFound>()),
      );
      expect((_value('S04-profile-notfound', 'shareImport')! as Map)['message'], 'LiveMe service');
      final noCounts = _envelope({
        'user': {
          'user_info': {'uid': _userId, 'short_id': _shortId, 'nickname': 'x'},
        },
      });
      expect(
        () => LiveMeApi.profile(noCounts, userId: _userId),
        throwsA(isA<ApiChanged>()),
        reason: '3.x required count_info',
      );
    });

    test('S03+S04+S05 live room entry matches 3.x but for the introduction (21-3); start and restriction added', () {
      final room = _liveRoom();
      final refresh = _liveRoom(media: false);
      for (final (key, actual) in [
        ('getRoomDetail', room),
        ('getRoomDetailForRecording', room),
        ('searchRooms(shortId)', refresh),
        ('searchRooms(link)', refresh),
        ('getRoomDetailForRefresh', refresh),
      ]) {
        final legacy = _value('S03-mapping-live', key);
        _expectParity(
          _projection(actual),
          legacy is List ? _maps(legacy).single : legacy! as Map<String, dynamic>,
          // 21-3: the anchor's signature, not user_info.desc (the name).
          changed: {..._changed, 'introduction'},
          reason: key,
        );
        expect(
          (actual.introduction, actual.startedAt, actual.restriction),
          (_liveProfile().bio, _liveStart, LiveRestriction.none),
        );
      }
      expect(_value('S03-mapping-live', 'getLiveStatus'), isTrue);
      expect(room.isLiveNow, isTrue);
      final legacy = _value('S03-mapping-live', 'getRoomDetail')! as Map<String, dynamic>;
      expect(legacy['introduction'], 'LIVEME-NIGHTCLUB 🔆⃤', reason: "3.x showed the broadcast's user_info.desc");
      expect(legacy['introduction'], legacy['nick'], reason: 'which is the name');
      expect(room.followers, '33933');
      expect(refresh.data, isNull, reason: 'a refresh carries no stream data');
      expect(room.toJson()['restriction'], 'none');
    });

    test('S03+S04 offline room matches 3.x', () {
      final profile = LiveMeApi.profile(_sample('S04-profile-offline').body, userId: _offlineUserId);
      final room = LiveMeApi.room(LiveMeApi.offline(profile));
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(room),
          _value('S03-mapping-offline', key)! as Map<String, dynamic>,
          changed: _changed,
          reason: key,
        );
      }
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect((room.title, room.cover, room.introduction), (profile.nickname, '', '👑 🐰 🇺🇦'));
      expect((room.startedAt, room.restriction), (null, null), reason: 'no broadcast');
      expect(room.audienceMetricType, AudienceMetricType.onlineViewers);
      expect(_value('S03-mapping-offline', 'getLiveStatus'), isFalse);
    });

    test('S05 broadcast: ids checked, completed by user_info, counts and start only while live', () {
      final video = _liveVideo();
      expect(
        (video.shortId, video.userId, video.videoId, video.state),
        (_shortId, _userId, _videoId, LiveMeState.live),
      );
      expect((video.currentViewers, video.totalViewers, video.heat, video.likes), (201, 8681, 885, 773));
      expect((video.startedAt, video.restriction), (_liveStart, LiveRestriction.none));
      expect(video.bio, isEmpty, reason: 'user_info.desc is the name (21-3)');
      final root = (jsonDecode(_sample('S05-query-live').body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      final info = root['video_info'] as Map<String, dynamic>;
      expect(
        int.parse(root['time'] as String) - int.parse(info['videolength'] as String),
        int.parse(info['vtime'] as String),
        reason: 'vtime is the start: the answer time less the running time',
      );
      expect(
        () => LiveMeApi.video(_sample('S05-query-live').body, videoId: _videoId, shortId: _offlineShortId),
        throwsA(isA<ApiChanged>()),
      );
      expect(
        () => LiveMeApi.video(_sample('S05-query-live').body, videoId: '17904580585651396477'),
        throwsA(isA<ApiChanged>()),
      );
      final fromUser = _snapshot(
        {'ushortid': null, 'userid': null, 'uname': '', 'uface': null},
        user: {
          'short_id': '54321',
          'userid': '2234567890123456789',
          'uname': 'User',
          'face': 'https://esx.esxscloud.com/u.jpg',
          'desc': 'User',
          'usign': 'bio',
        },
      );
      expect(
        (fromUser.shortId, fromUser.userId, fromUser.nickname, fromUser.title),
        ('54321', '2234567890123456789', 'User', 'User'),
      );
      expect((fromUser.avatar, fromUser.bio), ('https://esx.esxscloud.com/u.jpg', 'bio'));
      final offline = _snapshot({'online': 0, 'playnumber': 5, 'heat': 9, 'likenum': 3, 'ispvt': 1});
      expect(
        (offline.state, offline.currentViewers, offline.heat, offline.likes, offline.startedAt, offline.restriction),
        (LiveMeState.offline, null, null, 3, null, null),
      );
      expect(offline.streams, isEmpty);
    });

    test('21-3: the introduction is the signature; the broadcast only fills in without one', () {
      const profile = LiveMeProfile(shortId: '12345678', userId: '1234567890123456789', nickname: 'P', bio: 'sign');
      const silent = LiveMeProfile(shortId: '12345678', userId: '1234567890123456789', nickname: 'P');
      final video = _snapshot({}, user: {'desc': 'Anchor', 'usign': 'own'});
      expect(video.bio, 'own');
      expect(LiveMeApi.withProfile(video, profile).bio, 'sign');
      expect(LiveMeApi.withProfile(video, silent).bio, 'own');
      expect(LiveMeApi.withProfile(_snapshot({}, user: {'desc': 'Anchor'}), silent).bio, isEmpty);
    });

    test('unified rule: vtime is the start of a live broadcast, whole seconds only', () {
      expect(LiveMeApi.startedAt('1790458262'), _liveStart);
      expect(LiveMeApi.startedAt(1790458262), _liveStart);
      expect(LiveMeApi.startedAt(' 1790458262 '), _liveStart);
      for (final bad in [null, '', '0', 0, '-5', 'abc', '1790458262000', 1790458262.5, '17904582.62']) {
        expect(LiveMeApi.startedAt(bad), isNull, reason: '$bad');
      }
      expect(_snapshot({'vtime': '0'}).startedAt, isNull);
      expect(_snapshot({'vtime': null}).startedAt, isNull);
      expect(_snapshot({'vtime': 'x'}).state, LiveMeState.live, reason: 'a bad start drops only the start');
      expect(_snapshot({'status': 1}).startedAt, isNull, reason: 'only while live');
    });

    test('states: live, offline, unknown; private and paid are live and marked (21-5; 3.x: banned)', () {
      expect(_snapshot({}).state, LiveMeState.live);
      expect(_snapshot({'online': '0'}).state, LiveMeState.offline);
      expect(_snapshot({'status': 1}).state, LiveMeState.offline);
      expect(_snapshot({'roomstate': '2'}).state, LiveMeState.offline);
      expect(_snapshot({'online': null, 'status': null, 'roomstate': null}).state, LiveMeState.unknown);
      expect(_snapshot({'online': 2}).state, LiveMeState.unknown);
      for (final (changes, kind) in [
        (<String, Object?>{'ispvt': 1}, LiveRestriction.private),
        (<String, Object?>{'livebptype': '7'}, LiveRestriction.paid),
        (<String, Object?>{'hot_label_v2': _paidLabel}, LiveRestriction.paid),
      ]) {
        final snapshot = _snapshot(changes);
        expect((snapshot.state, snapshot.restriction), (LiveMeState.live, kind), reason: '$changes');
        final room = LiveMeApi.room(snapshot);
        expect((room.effectiveLiveStatus, room.isLiveNow, room.isRestricted), (LiveStatus.live, true, true));
        expect(room.followGroup, FollowGroup.live);
        expect(room.toJson()['restriction'], kind.name);
      }
      expect(_snapshot({'livebptype': '7', 'online': 0}).state, LiveMeState.offline, reason: '3.x: restricted');
      expect(
        LiveMeApi.room(_snapshot({'online': null, 'status': null, 'roomstate': null})).isLiveStatusPending,
        isTrue,
      );
    });

    test('21-2: an empty or unusable cover or avatar falls back to the next field (3.x: only when missing)', () {
      const small = 'https://esx.esxscloud.com/small.jpg';
      expect(_snapshot({'videocapture': null, 'smallcover': small}).cover, small);
      expect(_snapshot({'videocapture': '', 'smallcover': small}).cover, small, reason: '3.x: no cover');
      expect(_snapshot({'videocapture': 'https://example.com/a.jpg', 'smallcover': small}).cover, small);
      expect(_snapshot({'videocapture': '', 'smallcover': ''}).cover, isEmpty);
      const face = 'https://esx.esxscloud.com/face.jpg';
      expect(_snapshot({'uface': ''}, user: {'face': face}).avatar, face);
      expect(_snapshot({'uface': ''}, user: {'face': '', 'icon': face}).avatar, face, reason: "the answer's icon");
      final profile = LiveMeApi.profile(
        _envelope({
          'user': {
            'user_info': {
              'uid': _userId,
              'short_id': _shortId,
              'nickname': 'x',
              'big_face': '',
              'face': face,
              'big_cover': ' ',
              'cover': small,
            },
            'count_info': <String, Object?>{},
          },
        }),
        userId: _userId,
      );
      expect((profile.avatar, profile.cover), (face, small));
      final entered = LiveMeApi.withProfile(_snapshot({'videocapture': '', 'smallcover': ''}), profile);
      expect(entered.cover, small, reason: 'room entry fills it from the profile');
    });

    test('images: the CDN hosts only, made https; protocol-relative addresses read', () {
      expect(LiveMeApi.image('http://esx.esxscloud.com/a.jpg'), 'https://esx.esxscloud.com/a.jpg');
      expect(LiveMeApi.image('//img.liveme.com/a.jpg'), 'https://img.liveme.com/a.jpg', reason: '3.x dropped it');
      expect(LiveMeApi.image('https://linkv.fun/a.jpg'), 'https://linkv.fun/a.jpg');
      for (final bad in [
        'https://example.com/a.jpg',
        'https://evil-esxscloud.com/a.jpg',
        'https://user@esx.esxscloud.com/a.jpg',
        'https://esx.esxscloud.com/a.jpg#x',
        'ftp://esx.esxscloud.com/a.jpg',
        '',
        7,
        null,
      ]) {
        expect(LiveMeApi.image(bad), '', reason: '$bad');
      }
    });
  });

  group('streams', () {
    test('21-7 S05: 原画 (FLV, HLS) and 流畅 with the URLs 3.x gave its three qualities', () {
      final data = _liveData();
      final qualities = LiveMeApi.qualities(data);
      expect(
        [for (final quality in qualities) (quality.quality, quality.id, quality.sort)],
        [('原画', 'source', 300), ('流畅', 'smooth', 200)],
      );
      final legacy = {
        for (final quality in _maps(_legacy('S03-mapping-live')['getPlayQualites']))
          quality['id'] as String: quality['getPlayUrls'] as List,
      };
      expect(legacy.keys, ['source-flv', 'smooth-flv', 'hls']);
      final source = LiveMeApi.resolution(data, qualities.first);
      expect(source.urls, [...legacy['source-flv']!, ...legacy['hls']!]);
      expect(source.appliedQualityData, 'source');
      final smooth = LiveMeApi.resolution(data, qualities.last);
      expect(smooth.urls, legacy['smooth-flv']);
      expect(smooth.appliedQualityData, 'smooth');
    });

    test("21-7: 3.x's quality ids play the quality that holds their URLs", () {
      expect(LiveMeApi.legacyQualityIds, {'source-flv': 'source', 'hls': 'source', 'smooth-flv': 'smooth'});
      expect(
        [
          for (final id in ['source-flv', ' HLS ', 'smooth-flv', 'source', 'uhd']) LiveMeApi.qualityIdFromLegacy(id),
        ],
        ['source', 'source', 'smooth', 'source', 'uhd'],
      );
      final data = _liveData();
      for (final (old, now) in [('source-flv', 'source'), ('hls', 'source'), ('smooth-flv', 'smooth')]) {
        final resolution = LiveMeApi.resolution(data, LivePlayQuality(quality: 'x', id: old));
        final expected = LiveMeApi.resolution(data, LivePlayQuality(quality: 'x', id: now));
        expect(resolution.urls, expected.urls, reason: old);
        expect(resolution.appliedQualityData, now, reason: old);
      }
      final legacy = _maps(_legacy('S03-mapping-live')['getPlayQualites']);
      for (final quality in legacy) {
        final lines = LiveMeApi.resolution(data, LivePlayQuality(quality: 'x', id: quality['id'])).lines;
        final line = lines.firstWhere((line) => line.url == (quality['getPlayUrls'] as List).single);
        expect(line.lineId, quality['id'] == 'hls' ? 'hls' : 'flv', reason: 'the old transport is the line');
      }
    });

    test('lines carry the media headers, format and line id; no lease (21-8)', () {
      final data = _liveData();
      final lines = [for (final quality in LiveMeApi.qualities(data)) ...LiveMeApi.resolution(data, quality).lines];
      expect(lines.map((line) => (line.format, line.lineId)), [
        (StreamFormat.flv, 'flv'),
        (StreamFormat.hls, 'hls'),
        (StreamFormat.flv, 'flv'),
      ]);
      for (final line in lines) {
        expect(line.headers, {
          'user-agent': LiveMeApi.userAgent,
          'origin': 'https://www.liveme.com',
          'referer': 'https://www.liveme.com/livehot/streaming/$_shortId',
        }, reason: "3.x's PlaybackHeaderResolver for LiveMe");
        expect(line.codec, isNull, reason: 'the platform does not say');
        expect(line.lease, isNull, reason: 'wsABStime is not enforced and does not move');
      }
    });

    test('21-8 in the samples: wsABStime is fixed per broadcast, and the site hands out expired ones', () {
      String expiry(String url) => Uri.parse(url).queryParameters['wsABStime']!;
      final featured = jsonDecode(_sample('S01-featurelist-p1').body) as Map<String, dynamic>;
      final data = featured['data'] as Map<String, dynamic>;
      final rows = (data['video_info'] as List).cast<Map<String, dynamic>>();
      final live = rows.firstWhere((row) => row['vid'] == _videoId);
      final entered = _liveData().streams.first.flv.single;
      expect(expiry(live['videosource'] as String), expiry(entered), reason: 'the list and room entry agree');
      expect(
        int.parse(expiry(entered), radix: 16) - int.parse(live['vtime'] as String),
        closeTo(24 * 3600, 600),
        reason: 'a day after the start on game.live11, not after the answer',
      );
      final listed = int.parse(data['time'] as String);
      final expired = rows.where((row) => int.parse(expiry(row['videosource'] as String), radix: 16) < listed).single;
      expect(expired['ushortid'], '30269538');
      expect(listed - int.parse(expiry(expired['videosource'] as String), radix: 16), closeTo(4.95 * 3600, 60));
      expect(
        LiveMeApi.featuredPage(_sample('S01-featurelist-p1').body, page: 1).rooms.map((room) => room.roomId),
        contains('30269538'),
        reason: 'a live card whose URLs expired five hours ago',
      );
    });

    test("21-6: media on any host, kept as written; 3.x's CDN hosts made https as 3.x; *more flattened once", () {
      const flv = 'http://a.linkv.fun/yolo/1.flv?k=1';
      const other = 'http://b.liveme.com/yolo/1.flv?k=2';
      final streams = LiveMeApi.streams({
        'videosource': flv,
        'videosourcemore': jsonEncode([flv, other, 'http://cdn.example.com/1.flv', 'http://c.emolm.com/1.m3u8']),
        'smallsource': {'a': 'http://a.linkv.fun/yolo/1_360.flv', 'b': ' '},
        'smallsourcemore': ['http://a.linkv.fun/yolo/1_360.flv#x', 'http://u@a.linkv.fun/yolo/1_360.flv'],
        'hlsvideosource': 'http://hls.linkv.fun/yolo/1/playlist.m3u8 ',
      });
      expect(
        [
          for (final stream in streams) [stream.qualityId, stream.flv, stream.hls],
        ],
        [
          [
            'source',
            [
              'https://a.linkv.fun/yolo/1.flv?k=1',
              'https://b.liveme.com/yolo/1.flv?k=2',
              'http://cdn.example.com/1.flv',
            ],
            ['https://hls.linkv.fun/yolo/1/playlist.m3u8'],
          ],
          [
            'smooth',
            ['https://a.linkv.fun/yolo/1_360.flv'],
            <String>[],
          ],
        ],
      );
      expect(LiveMeApi.streams({'hlsvideosource': 'https://a.linkv.fun/1.flv', 'videosource': ''}), isEmpty);
      for (final (raw, format, expected) in [
        ('http://pull.newcdn.example/live/1.flv?s=1', StreamFormat.flv, 'http://pull.newcdn.example/live/1.flv?s=1'),
        ('https://pull.newcdn.example/1/index.m3u8', StreamFormat.hls, 'https://pull.newcdn.example/1/index.m3u8'),
        ('http://a.linkv.fun:8080/1.flv', StreamFormat.flv, 'http://a.linkv.fun:8080/1.flv'),
        ('http://evil-linkv.fun/1.flv', StreamFormat.flv, 'http://evil-linkv.fun/1.flv'),
        ('http://A.LINKV.FUN/1.FLV', StreamFormat.flv, 'https://a.linkv.fun/1.FLV'),
      ]) {
        expect(LiveMeApi.mediaUrl(raw, format), expected, reason: raw);
      }
      for (final (raw, format) in [
        ('https://a.linkv.fun/1 2.flv', StreamFormat.flv),
        ('https://a.linkv.fun/1.m3u8', StreamFormat.flv),
        ('https://a.linkv.fun/1.flv', StreamFormat.hls),
        ('rtmp://a.linkv.fun/1.flv', StreamFormat.flv),
        ('https:///1.flv', StreamFormat.flv),
        ('https://u:p@cdn.example/1.flv', StreamFormat.flv),
        ('https://cdn.example/1.flv#x', StreamFormat.flv),
        ('', StreamFormat.flv),
      ]) {
        expect(LiveMeApi.mediaUrl(raw, format), isNull, reason: raw);
      }
      final data = LiveMeRoomData(
        shortId: '12345678',
        userId: '1234567890123456789',
        state: LiveMeState.live,
        restriction: LiveRestriction.none,
        streams: streams,
      );
      final lines = LiveMeApi.resolution(data, LiveMeApi.qualities(data).first).lines;
      expect(lines.map((line) => line.lineId), ['flv', 'flv#2', 'flv#3', 'hls']);
      expect(lines.map((line) => line.format), [
        StreamFormat.flv,
        StreamFormat.flv,
        StreamFormat.flv,
        StreamFormat.hls,
      ]);
    });

    test('a quality with only one transport; a bad URL only drops its line', () {
      final hlsOnly = LiveMeApi.streams({
        'hlsvideosource': 'https://a.linkv.fun/1.m3u8',
        'videosource': 'ftp://x/1.flv',
      });
      expect(
        [
          for (final stream in hlsOnly) [stream.qualityId, stream.flv, stream.hls],
        ],
        [
          [
            'source',
            <String>[],
            ['https://a.linkv.fun/1.m3u8'],
          ],
        ],
      );
      final smoothOnly = LiveMeApi.streams({'smallsource': 'https://a.linkv.fun/1_360.flv'});
      expect(smoothOnly.single.qualityId, 'smooth');
      final data = LiveMeRoomData(shortId: '12345678', userId: '1', state: LiveMeState.live, streams: smoothOnly);
      expect(LiveMeApi.qualities(data).single.quality, '流畅');
      expect(
        () => LiveMeApi.resolution(data, const LivePlayQuality(quality: 'x', id: 'source-flv')),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('a broadcast that cannot play says why; an unknown quality is unavailable', () {
      final streams = _liveData().streams;
      LiveMeRoomData data(LiveMeState state, {LiveRestriction? restriction, List<LiveMeStream> media = const []}) =>
          LiveMeRoomData(shortId: '12345678', userId: '1', state: state, restriction: restriction, streams: media);
      for (final state in LiveMeState.values) {
        expect(() => LiveMeApi.qualities(data(state)), throwsA(isA<StreamUnavailable>()), reason: state.name);
      }
      for (final kind in [LiveRestriction.private, LiveRestriction.paid]) {
        expect(
          () => LiveMeApi.qualities(data(LiveMeState.live, restriction: kind, media: streams)),
          throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('(${kind.name})'))),
          reason: 'the unified rule: the reason goes with the error',
        );
      }
      expect(
        LiveMeApi.qualities(data(LiveMeState.live, restriction: LiveRestriction.none, media: streams)),
        hasLength(2),
      );
      expect(LiveMeApi.qualities(data(LiveMeState.live, media: streams)), hasLength(2), reason: 'not said: none');
      expect(LiveMeApi.restricted('1', null), isNull);
      expect(LiveMeApi.restricted('1', LiveRestriction.none), isNull);
      const other = LivePlayQuality(quality: 'x', id: 'uhd');
      expect(() => LiveMeApi.resolution(_liveData(), other), throwsA(isA<StreamUnavailable>()));
      expect(_snapshot({}, media: false).streams, isEmpty, reason: 'media only when asked');
      for (final changes in [
        <String, Object?>{'ispvt': 1},
        <String, Object?>{'hot_label_v2': _paidLabel},
      ]) {
        expect(
          _snapshot({...changes, 'videosource': 'http://a.linkv.fun/1.flv'}).streams,
          isEmpty,
          reason: 'a restricted broadcast is not played: $changes',
        );
      }
      expect(_snapshot({'videosource': 'http://a.linkv.fun/1.flv'}).streams, hasLength(1));
    });
  });

  group('links', () {
    test('S05 vectors match 3.x; an undecodable path is no link (3.x threw)', () {
      Object? project(LiveMeLink? link) => link == null ? null : {'kind': link.kind.name, 'id': link.id};
      for (final vector in _maps(_legacy('S05-query-live')['vectors'])) {
        final input = vector['input'] as String;
        if (input.contains('%FF')) {
          expect((vector['parse'] as Map)['throws'], 'FormatException');
          expect(LiveMeLink.parse(input), isNull);
          expect(LiveMeLink.parseOrShortId(input), isNull);
          continue;
        }
        expect(project(LiveMeLink.parse(input)), vector['parse'], reason: input);
        expect(project(LiveMeLink.parseOrShortId(input)), vector['parseOrShortId'], reason: input);
      }
    });

    test('the share URL the broadcast hands out is a video link', () {
      final root = jsonDecode(_sample('S05-query-live').body) as Map<String, dynamic>;
      final video = (root['data'] as Map<String, dynamic>)['video_info'] as Map<String, dynamic>;
      final shareUrl = video['shareurl'] as String;
      expect(LiveMeLink.parse(shareUrl), const LiveMeLink(LiveMeLinkKind.videoId, _videoId));
      expect(LiveMeLink.url(_shortId), 'https://www.liveme.com/livehot/streaming/$_shortId');
      expect(video['TCRoomId'], _videoId, reason: "the broadcast's chat room is its video id (for M5)");
    });
  });

  group('signature', () {
    test("reproduces the recorded request's lm-s-sign", () {
      final request = _sample('S05-query-live').meta['request'] as Map<String, dynamic>;
      final form = Uri.splitQueryString(request['body'] as String);
      final signed = LiveMeSigner.signAt(
        query: LiveMeApi.videoQuery,
        form: {
          for (final key in ['_time', 'thirdchannel', 'videoid', 'area', 'vali']) key: form[key]!,
        },
        timestamp: form['lm_s_ts']!,
      );
      expect(signed.fields, form);
      expect(signed.signature, (request['headers'] as Map)['lm-s-sign']);
    });

    test('an independent vector (Python hashlib, archive v4)', () {
      final signed = LiveMeSigner.signAt(
        query: LiveMeApi.videoQuery,
        form: const {
          '_time': '1790529930544',
          'thirdchannel': '6',
          'videoid': _videoId,
          'area': 'en',
          'vali': 'ABCDlEFGHmJKMNP',
        },
        timestamp: '17905299305440',
      );
      expect(signed.fields['lm_s_str'], '4c71dbf9913b0b4ad7099adfb411b750');
      expect(signed.signature, 'aaa4b40cb4ab6fa268ab712f39f93b6e');
    });

    test("timestamps are the millisecond and one counter digit, the web client's 14 digits", () {
      final signer = LiveMeSigner(random: Random(1));
      final now = DateTime.utc(2026, 9, 27, 17, 25, 41, 900);
      final stamps = [
        for (var i = 0; i < 12; i++) signer.sign(query: const {}, form: const {}, now: now).fields['lm_s_ts']!,
      ];
      expect(stamps.first, '${now.millisecondsSinceEpoch}0');
      expect(stamps.map((stamp) => stamp.length).toSet(), {14}, reason: "3.x's counter grew to 4 digits");
      expect(stamps[10], stamps[0], reason: 'the digit wraps after 9');
      expect(
        signer.vali(),
        matches(
          RegExp(
            r'^[A-HJKMNP-TW-Za-fh-kmnprstw-z2-8]{4}l[A-HJKMNP-TW-Za-fh-kmnprstw-z2-8]{4}m[A-HJKMNP-TW-Za-fh-kmnprstw-z2-8]{5}$',
          ),
        ),
      );
    });
  });

  group('errors', () {
    test('HTTP statuses as 3.x read them', () {
      for (final (status, matcher) in [
        (400, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (420, isA<RateLimited>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        expect(() => LiveMeApi.mapping('', status: status), throwsA(matcher), reason: '$status');
      }
    });

    test('business statuses as 3.x read them; "not exist" is NotFound', () {
      for (final (status, message, matcher) in [
        ('400', 'params error', isA<NotFound>()),
        (404, '', isA<NotFound>()),
        ('401', '', isA<RiskControl>()),
        ('403', '', isA<RiskControl>()),
        ('420', '', isA<RateLimited>()),
        ('429', '', isA<RateLimited>()),
        ('500', 'user not exist', isA<NotFound>()),
        ('500', 'busy', isA<NetworkFailure>()),
        ('502', '', isA<NetworkFailure>()),
        ('201', '', isA<ApiChanged>()),
        ('ok', '', isA<ApiChanged>()),
      ]) {
        expect(
          () => LiveMeApi.searchPage(_envelope({'data_info': <Object?>[]}, status: status, message: message)),
          throwsA(matcher),
          reason: '$status $message',
        );
      }
      for (final body in [
        'not json',
        '[]',
        jsonEncode({'data': <String, Object?>{}}),
        _envelope(null),
        'x' * (8 * 1024 * 1024 + 1),
      ]) {
        expect(
          () => LiveMeApi.searchPage(body),
          throwsA(isA<ApiChanged>()),
          reason: body.length > 99 ? 'oversize' : body,
        );
      }
    });
  });
}
