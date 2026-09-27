import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'liveme';

/// A streamer profile from `user/getinfo` (spec/sites/liveme.md §4.2).
typedef LiveMeProfile = ({
  String shortId,
  String userId,
  String name,
  Uri? avatar,
  Uri? cover,
  String? bio,
  String? country,
});

/// Pure parsing of LiveMe responses (spec/sites/liveme.md).
abstract final class LiveMeParse {
  /// §1 short id: the room identity.
  static final RegExp shortId = RegExp(r'^[1-9]\d{4,11}$');

  /// §1 user and video ids.
  static final RegExp longId = RegExp(r'^[1-9]\d{12,23}$');

  /// §5 qualities, best first.
  static const source = Quality(id: 'source', label: '原画', rank: 2);

  /// §5 the 360p FLV.
  static const smooth = Quality(id: 'smooth', label: '流畅', rank: 1);

  /// The room page for [shortId].
  static Uri link(String shortId) => Uri.parse('https://www.liveme.com/livehot/streaming/$shortId');

  /// §9 envelope: `status` is a string; "200" is success.
  static Map<String, dynamic> _envelope(String body, String what) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not an object');
    final status = jsonInt(decoded['status']);
    final message = jsonString(decoded['msg']) ?? '';
    return switch (status) {
      200 => decoded,
      400 || 404 => throw NotFound(_site, '$what: $status $message'),
      401 || 403 => throw RiskControl(_site, detail: '$what: $status $message'),
      420 || 429 => throw RateLimited(_site, detail: '$what: $status $message'),
      500 when message.contains('not exist') => throw NotFound(_site, '$what: $message'),
      final int code when code >= 500 => throw NetworkFailure(_site, '$what: $status $message'),
      _ => throw ApiChanged(_site, '$what: status $status $message'),
    };
  }

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: expected an object');
  }

  static String? _text(Object? value) {
    final text = jsonString(value);
    return text == null ? null : decodeHtmlEntities(text);
  }

  static int? _count(Object? value) {
    final number = jsonInt(value);
    return number != null && number >= 0 ? number : null;
  }

  static Audience _audience(Map<String, dynamic> video) => Audience(
    online: _count(video['playnumber']),
    popularity: _count(video['heat']),
    cumulative: _count(video['watchnumber']),
  );

  /// §4.3 a private or paid broadcast: live, but not watchable anonymously.
  static bool restricted(Map<String, dynamic> video) {
    final label = video['hot_label_v2'];
    return jsonInt(video['ispvt']) == 1 ||
        jsonInt(video['livebptype']) == 7 ||
        (label is Map && jsonString(label['text'])?.toLowerCase() == 'paid broadcast');
  }

  /// §4.3 the state of a `video_info` object.
  static LiveState state(Map<String, dynamic> video) {
    final online = jsonInt(video['online']);
    final status = jsonInt(video['status']);
    final roomState = jsonInt(video['roomstate']);
    if (online == 1 && status == 0 && roomState == 0) return LiveState.live;
    if (online == 0 || (status != null && status != 0) || (roomState != null && roomState != 0)) {
      return LiveState.offline;
    }
    throw ApiChanged(_site, 'video_info: online $online status $status roomstate $roomState');
  }

  static RoomCard _videoCard(Map<String, dynamic> video) {
    final id = jsonString(video['ushortid'])!;
    final name = _text(video['uname']) ?? '';
    final started = jsonInt(video['vtime']) ?? 0;
    return RoomCard(
      ref: RoomRef(_site, id),
      title: _text(video['title']) ?? name,
      anchorName: name,
      state: state(video),
      cover: jsonUrl(video['videocapture']) ?? jsonUrl(video['smallcover']),
      area: jsonString(video['countryCode']),
      audience: _audience(video),
      liveSince: started > 0 ? DateTime.fromMillisecondsSinceEpoch(started * 1000, isUtc: true) : null,
      avatar: jsonUrl(video['uface']),
    );
  }

  /// §2.2 `featurelist`: cards without a short id and private or paid rooms
  /// are skipped; `next_page == 1` means another page.
  static Page<RoomCard> featured(String body, {required int page}) {
    final data = _map(_envelope(body, 'featurelist')['data'], 'featurelist.data');
    final rows = data['video_info'];
    if (rows is! List) throw const ApiChanged(_site, 'featurelist: video_info is not a list');
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = jsonString(row['ushortid']);
      if (id == null || !shortId.hasMatch(id) || restricted(row) || !seen.add(id)) continue;
      cards.add(_videoCard(row));
    }
    final more = jsonInt(data['next_page']) == 1 && rows.isNotEmpty;
    return Page(cards, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §3 `searchKeyword`: streamers, live or not; an empty page is the last.
  static Page<RoomCard> search(String body, {required int page}) {
    final data = _map(_envelope(body, 'searchKeyword')['data'], 'searchKeyword.data');
    final rows = data['data_info'];
    if (rows is! List) throw const ApiChanged(_site, 'searchKeyword: data_info is not a list');
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = jsonString(row['short_id']);
      if (id == null || !shortId.hasMatch(id) || !seen.add(id)) continue;
      final name = _text(row['nickname']) ?? _text(row['uname']) ?? '';
      cards.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: name,
          anchorName: name,
          state: jsonInt(row['is_live']) == 1 ? LiveState.live : LiveState.offline,
          area: jsonString(row['countryCode']),
          avatar: jsonUrl(row['face']),
        ),
      );
    }
    return Page(cards, next: rows.isEmpty ? null : PageCursor('${page + 1}'));
  }

  /// §4.1 `uid_vid_by_short_id`: the user id and the current broadcast id
  /// (null when not broadcasting).
  static ({String userId, String? videoId}) mapping(String body) {
    final data = _map(_envelope(body, 'uid_vid_by_short_id')['data'], 'uid_vid_by_short_id.data');
    final userId = jsonString(data['uid']);
    if (userId == null || !longId.hasMatch(userId)) throw ApiChanged(_site, 'uid_vid_by_short_id: uid $userId');
    final videoId = jsonString(data['vid']);
    return (userId: userId, videoId: videoId != null && longId.hasMatch(videoId) ? videoId : null);
  }

  /// §4.2 `user/getinfo`.
  static LiveMeProfile profile(String body) {
    final data = _map(_envelope(body, 'getinfo')['data'], 'getinfo.data');
    final info = _map(_map(data['user'], 'getinfo.user')['user_info'], 'getinfo.user_info');
    final id = jsonString(info['short_id']);
    final userId = jsonString(info['uid']) ?? jsonString(info['cm_openid']);
    if (id == null || !shortId.hasMatch(id) || userId == null) throw const ApiChanged(_site, 'getinfo: no ids');
    final country = jsonString(info['countryCode'])?.toUpperCase();
    return (
      shortId: id,
      userId: userId,
      name: _text(info['nickname']) ?? _text(info['uname']) ?? '',
      avatar: jsonUrl(info['big_face']) ?? jsonUrl(info['face']),
      cover: jsonUrl(info['big_cover']) ?? jsonUrl(info['cover']),
      bio: _text(info['usign']),
      country: country != null && RegExp(r'^[A-Z]{2}$').hasMatch(country) ? country : null,
    );
  }

  /// §4.3 `queryinfosimple`: the `video_info` object.
  static Map<String, dynamic> video(String body, {required String expectedVideoId}) {
    final data = _map(_envelope(body, 'queryinfosimple')['data'], 'queryinfosimple.data');
    final video = _map(data['video_info'], 'queryinfosimple.video_info');
    final id = jsonString(video['vid']) ?? jsonString(video['vdoid']);
    if (id != expectedVideoId) throw ApiChanged(_site, 'queryinfosimple: asked $expectedVideoId, got $id');
    return video;
  }

  /// §4 the detail from the profile and, when broadcasting, the video.
  static RoomDetail detail(LiveMeProfile profile, Map<String, dynamic>? video) {
    final card = video == null
        ? RoomCard(
            ref: RoomRef(_site, profile.shortId),
            title: profile.name,
            anchorName: profile.name,
            state: LiveState.offline,
            cover: profile.cover,
            area: profile.country,
          )
        : _videoCard(video);
    if (card.ref.roomId != profile.shortId) {
      throw ApiChanged(_site, 'short id ${card.ref.roomId} does not match profile ${profile.shortId}');
    }
    return RoomDetail(
      card: RoomCard(
        ref: card.ref,
        title: card.title,
        anchorName: card.anchorName.isEmpty ? profile.name : card.anchorName,
        state: card.state,
        cover: card.cover ?? profile.cover,
        area: card.area ?? profile.country,
        audience: card.audience,
        liveSince: card.liveSince,
      ),
      link: link(profile.shortId),
      avatar: profile.avatar ?? card.avatar,
      introduction: profile.bio,
    );
  }

  /// §6.3 lease: `wsABStime` is the hex expiry of the Wangsu signature.
  static Lease? lease(Uri url) {
    final raw = url.queryParameters['wsABStime'];
    final seconds = raw == null ? null : int.tryParse(raw, radix: 16);
    if (seconds == null) return null;
    final expires = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    return Lease(refreshAt: expires.subtract(const Duration(minutes: 10)), expiresAt: expires, cutsConnection: false);
  }

  static Uri? _media(Object? value, String extension) {
    final url = jsonUrl(value);
    if (url == null || !url.path.toLowerCase().endsWith(extension)) return null;
    return url;
  }

  /// §5 the qualities a live video offers, best first.
  static List<Quality> qualities(Map<String, dynamic> video) => [
    if (_media(video['videosource'], '.flv') != null || _media(video['hlsvideosource'], '.m3u8') != null) source,
    if (_media(video['smallsource'], '.flv') != null) smooth,
  ];

  /// §5 lines of [quality]: the source FLV and HLS, or the 360p FLV.
  static List<StreamLine> lines(Map<String, dynamic> video, Quality quality, {required Map<String, String> headers}) {
    if (state(video) != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    if (restricted(video)) throw const NeedsLogin(_site, 'private or paid broadcast');
    final urls = quality.id == smooth.id
        ? [(_media(video['smallsource'], '.flv'), StreamFormat.flv)]
        : [
            (_media(video['videosource'], '.flv') ?? _media(video['videosourcemore'], '.flv'), StreamFormat.flv),
            (_media(video['hlsvideosource'], '.m3u8'), StreamFormat.hls),
          ];
    final result = <StreamLine>[
      for (final (url, format) in urls)
        if (url != null)
          StreamLine(
            url: url,
            format: format,
            lineId: format.name,
            requested: quality,
            headers: headers,
            codec: 'avc',
            lease: lease(url),
          ),
    ];
    if (result.isEmpty) throw StreamUnavailable(_site, 'no ${quality.id} URL');
    return result;
  }
}
