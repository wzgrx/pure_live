import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_vod/src/models.dart';
import 'package:live_vod/src/pgc_models.dart';
import 'package:live_vod/src/streams.dart';

/// Platform id of every Bilibili request (proxy route, throttle, cookie).
const String vodSite = 'bilibili';

/// Pure parsing of the Bilibili video-site answers (pure_live_TV `b9d2f739`
/// `lib/modules/vod/models/*` and the `from*Json` factories, rewritten
/// without code generation). Each function takes the response text and
/// status and returns models or throws a `SiteError`.
abstract final class VodParse {
  // Envelope ------------------------------------------------------------------

  /// The `{code, message, data|result}` envelope: HTTP 412 or code -412 →
  /// `RateLimited`; 5xx → `NetworkFailure`; -352 → `RiskControl`; -101 →
  /// `NeedsLogin`; -404/62002/62004/-10403… per [notFound]; any other
  /// non-zero code → `ApiChanged`. Returns `data` (or `result`).
  static Object? data(String body, {required int status, required String what, Set<int> notFound = const {-404}}) {
    if (status == 412) throw RateLimited(vodSite, detail: '$what: HTTP 412');
    if (status >= 500) throw NetworkFailure(vodSite, '$what: HTTP $status');
    final ok = status >= 200 && status < 300;
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) {
      throw ApiChanged(vodSite, '$what: ${ok ? 'not a JSON object' : 'HTTP $status'} (${snippet(body)})');
    }
    final code = jsonInt(decoded['code']);
    if (code == 0 && ok) return decoded.containsKey('data') ? decoded['data'] : decoded['result'];
    final detail = '$what: code $code ${jsonString(decoded['message']) ?? jsonString(decoded['msg']) ?? ''}'.trim();
    switch (code) {
      case -352:
        throw RiskControl(vodSite, detail: detail);
      case -412 || -509 || -799:
        throw RateLimited(vodSite, detail: detail);
      case -101 || -111:
        throw NeedsLogin(vodSite, detail);
      case final int value when notFound.contains(value):
        throw NotFound(vodSite, detail);
    }
    throw ApiChanged(vodSite, ok ? detail : 'HTTP $status, $detail');
  }

  /// [body] shortened for error details.
  static String snippet(String body) {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.length <= 80 ? text : '${text.substring(0, 80)}…';
  }

  // Archives ------------------------------------------------------------------

  /// A list row of popular, ranking, related, recommendation and `view`:
  /// owner and stat nested, `pic` cover, seconds duration.
  static VodArchive? archive(Object? value) {
    final json = object(value);
    final bvid = jsonString(json?['bvid']);
    if (json == null || bvid == null) return null;
    final owner = object(json['owner']);
    final stat = object(json['stat']);
    final pages = list(json['pages']);
    final title = plain(json['title']);
    final parts = [
      for (final page in pages.map(object).nonNulls)
        VodPart(
          cid: jsonInt(page['cid']) ?? 0,
          page: jsonInt(page['page']) ?? 1,
          title: jsonString(page['part']) ?? title,
          duration: Duration(seconds: jsonInt(page['duration']) ?? 0),
        ),
    ];
    return VodArchive(
      bvid: bvid,
      aid: jsonInt(json['aid']) ?? jsonInt(json['id']) ?? 0,
      title: title,
      cover: normalizeImageUrl(json['pic'] ?? json['cover']),
      owner: VodOwner(
        mid: jsonInt(owner?['mid']) ?? 0,
        name: jsonString(owner?['name']) ?? '',
        face: normalizeImageUrl(owner?['face']),
      ),
      duration: Duration(seconds: jsonInt(json['duration']) ?? 0),
      stat: VodStat(
        views: jsonInt(stat?['view']) ?? 0,
        danmaku: jsonInt(stat?['danmaku']) ?? 0,
        replies: jsonInt(stat?['reply']) ?? 0,
        likes: jsonInt(stat?['like']) ?? 0,
        coins: jsonInt(stat?['coin']) ?? 0,
        favorites: jsonInt(stat?['favorite']) ?? 0,
      ),
      typeId: jsonInt(json['tid']) ?? 0,
      typeName: jsonString(json['tname']) ?? jsonString(json['tnamev2']) ?? '',
      description: jsonString(json['desc']) ?? '',
      publishedAt: unixTime(json['pubdate']),
      cid: parts.isEmpty ? jsonInt(json['cid']) ?? 0 : parts.first.cid,
      partCount: parts.isEmpty ? jsonInt(json['videos']) ?? 1 : parts.length,
      parts: parts,
    );
  }

  /// `x/web-interface/popular`: 20 a page, `no_more` at the end.
  static VodPage<VodArchive> popular(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'popular'));
    return VodPage([for (final item in list(data?['list'])) ?archive(item)], hasMore: data?['no_more'] == false);
  }

  /// `x/web-interface/ranking/v2`: a fixed list.
  static List<VodArchive> ranking(String body, {int status = 200}) => [
    for (final item in list(object(VodParse.data(body, status: status, what: 'ranking'))?['list'])) ?archive(item),
  ];

  /// `x/web-interface/wbi/index/top/feed/rcmd`: videos only (ads and live
  /// cards have `goto` other than `av`).
  static List<VodArchive> recommended(String body, {int status = 200}) => [
    for (final item in list(object(VodParse.data(body, status: status, what: 'rcmd'))?['item']))
      if (jsonString(object(item)?['goto']) == 'av') ?archive(item),
  ];

  /// `x/web-interface/archive/related`: `data` is the list (older answers
  /// wrapped it in `data.list`).
  static List<VodArchive> related(String body, {int status = 200}) {
    final data = VodParse.data(body, status: status, what: 'related');
    return [for (final item in data is List ? data : list(object(data)?['list'])) ?archive(item)];
  }

  /// `x/web-interface/view`: the archive with every part. -404 and 62002
  /// (hidden), 62004 (under review), 62012 (uploader only) are `NotFound`.
  static VodArchive view(String body, {int status = 200}) {
    final data = VodParse.data(body, status: status, what: 'view', notFound: const {-404, 62002, 62004, 62012});
    return archive(data) ?? (throw ApiChanged(vodSite, 'view: no bvid (${snippet(body)})'));
  }

  /// `x/web-interface/wbi/search/type?search_type=video`: flat rows, `mm:ss`
  /// durations, highlighted titles, `typename`.
  static VodPage<VodArchive> searchVideos(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'search video'));
    final rows = [
      for (final item in list(data?['result']).map(object).nonNulls)
        if (jsonString(item['type']) == 'video' && jsonString(item['bvid']) != null)
          VodArchive(
            bvid: jsonString(item['bvid'])!,
            aid: jsonInt(item['aid']) ?? 0,
            title: plain(item['title']),
            cover: normalizeImageUrl(item['pic']),
            owner: VodOwner(
              mid: jsonInt(item['mid']) ?? 0,
              name: jsonString(item['author']) ?? '',
              face: normalizeImageUrl(item['upic']),
            ),
            duration: clockDuration(jsonString(item['duration']) ?? ''),
            stat: VodStat(
              views: jsonInt(item['play']) ?? 0,
              danmaku: jsonInt(item['video_review']) ?? 0,
              favorites: jsonInt(item['favorites']) ?? 0,
              likes: jsonInt(item['like']) ?? 0,
              replies: jsonInt(item['review']) ?? 0,
            ),
            typeId: jsonInt(item['typeid']) ?? 0,
            typeName: jsonString(item['typename']) ?? '',
            description: jsonString(item['description']) ?? '',
            publishedAt: unixTime(item['pubdate']),
          ),
    ];
    return VodPage(rows, hasMore: (jsonInt(data?['page']) ?? 1) < (jsonInt(data?['numPages']) ?? 0));
  }

  /// `search_type=bili_user`.
  static VodPage<VodSearchUser> searchUsers(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'search user'));
    return VodPage([
      for (final item in list(data?['result']).map(object).nonNulls)
        VodSearchUser(
          owner: VodOwner(
            mid: jsonInt(item['mid']) ?? 0,
            name: plain(item['uname']),
            face: normalizeImageUrl(item['upic']),
          ),
          sign: jsonString(item['usign']) ?? '',
          fans: jsonInt(item['fans']) ?? 0,
          videos: jsonInt(item['videos']) ?? 0,
          level: jsonInt(item['level']) ?? 0,
          liveRoomId: jsonInt(item['room_id']) ?? 0,
          isLive: jsonInt(item['is_live']) == 1,
        ),
    ], hasMore: (jsonInt(data?['page']) ?? 1) < (jsonInt(data?['numPages']) ?? 0));
  }

  /// `search_type=media_bangumi` / `media_ft`: season cards.
  static VodPage<PgcCard> searchSeasons(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'search pgc'));
    return VodPage([
      for (final item in list(data?['result']).map(object).nonNulls)
        if (jsonInt(item['season_id']) case final int id when id > 0)
          PgcCard(
            seasonId: id,
            mediaId: jsonInt(item['media_id']) ?? 0,
            title: plain(item['title']),
            cover: normalizeImageUrl(item['cover']),
            badge: jsonString(object(list(item['display_info']).firstOrNull)?['text']) ?? '',
            subtitle: jsonString(item['styles']) ?? '',
            indexShow: jsonString(item['index_show']) ?? '',
            score: jsonString(object(item['media_score'])?['score']) ?? '',
            isFinished: jsonInt(item['is_finish']) == 1,
            type: jsonInt(item['season_type']) ?? 0,
          ),
    ], hasMore: (jsonInt(data?['page']) ?? 1) < (jsonInt(data?['numPages']) ?? 0));
  }

  /// `x/web-interface/search/square`: trending words.
  static List<VodHotword> hotwords(String body, {int status = 200}) => [
    for (final item in list(
      object(object(VodParse.data(body, status: status, what: 'hotwords'))?['trending'])?['list'],
    ).map(object).nonNulls)
      if (jsonString(item['keyword']) case final String keyword)
        VodHotword(
          keyword: keyword,
          label: jsonString(item['show_name']) ?? keyword,
          icon: normalizeImageUrl(item['icon']),
        ),
  ];

  /// `s.search.bilibili.com/main/suggest`: `result.tag[].value`. Not an
  /// envelope with `data`; a broken answer is no suggestion.
  static List<String> suggestions(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const [];
    }
    final tags = list(object(object(decoded)?['result'])?['tag']);
    return [
      for (final tag in tags.map(object).nonNulls)
        if (jsonString(tag['value']) ?? jsonString(tag['term']) case final String value) value,
    ];
  }

  // Player ----------------------------------------------------------------------

  /// `x/player/wbi/v2`: subtitles, BGM, resume point, viewers.
  static VodPlayerInfo playerInfo(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'player v2'));
    final bgm = object(data?['bgm_info']);
    final title = jsonString(bgm?['music_title']) ?? '';
    return VodPlayerInfo(
      subtitles: [
        for (final item in list(object(data?['subtitle'])?['subtitles']).map(object).nonNulls)
          if (normalizeImageUrl(item['subtitle_url']) case final String url when url.isNotEmpty)
            VodSubtitleTrack(
              language: jsonString(item['lan']) ?? '',
              label: jsonString(item['lan_doc']) ?? '',
              url: url,
              aiGenerated: (jsonString(item['lan']) ?? '').startsWith('ai-') || (jsonInt(item['ai_type']) ?? 0) > 0,
            ),
      ],
      bgmMusicId: jsonString(bgm?['music_id']) ?? '',
      bgmTitle: _quoted.firstMatch(title)?.group(1) ?? title,
      lastPlayCid: jsonInt(data?['last_play_cid']) ?? 0,
      lastPlayTime: Duration(milliseconds: jsonInt(data?['last_play_time']) ?? 0),
      onlineCount: jsonInt(data?['online_count']) ?? 0,
    );
  }

  static final RegExp _quoted = RegExp('《(.+?)》');

  /// A subtitle file: `{body: [{from, to, content}]}` (seconds).
  static List<VodSubtitleCue> subtitleCues(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(vodSite, 'subtitle: not JSON (${snippet(body)})');
    }
    return [
      for (final cue in list(object(decoded)?['body']).map(object).nonNulls)
        VodSubtitleCue(start: _seconds(cue['from']), end: _seconds(cue['to']), text: jsonString(cue['content']) ?? ''),
    ];
  }

  static Duration _seconds(Object? value) => switch (value) {
    final num seconds => Duration(microseconds: (seconds * 1000000).round()),
    final String text => Duration(microseconds: ((double.tryParse(text) ?? 0) * 1000000).round()),
    _ => Duration.zero,
  };

  /// A playurl answer (`x/player/playurl`, `pgc/player/web/playurl`) for
  /// one part. [headers] go to every media request.
  static VodStreams streams(String body, {required Map<String, String> headers, int status = 200}) {
    final value = VodParse.data(body, status: status, what: 'playurl', notFound: const {-404, 87005});
    final data = object(value) ?? (throw const ApiChanged(vodSite, 'playurl: no data'));
    final dash = object(data['dash']);
    final formats = [
      for (final format in list(data['support_formats']).map(object).nonNulls)
        if (jsonInt(format['quality']) case final int qn)
          VodQuality(
            qn: qn,
            label: jsonString(format['new_description']) ?? jsonString(format['description']) ?? VodQuality.labelOf(qn),
            needsVip: format['need_vip'] == true,
            needsLogin: format['need_login'] == true,
          ),
    ];
    final qualities = formats.isNotEmpty
        ? formats
        : [
            for (final qn in list(data['accept_quality']).map(jsonInt).nonNulls)
              VodQuality(qn: qn, label: VodQuality.labelOf(qn)),
          ];
    final videos = [for (final item in list(dash?['video'])) ?_rendition(item)]..sort((a, b) => b.id.compareTo(a.id));
    final audios = [for (final item in list(dash?['audio'])) ?_rendition(item)]
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    final segments = [
      for (final item in list(data['durl']).map(object).nonNulls)
        if (jsonString(item['url']) case final String url)
          VodSegment(
            url: url,
            backupUrls: [for (final backup in list(item['backup_url'])) ?jsonString(backup)],
            order: jsonInt(item['order']) ?? 1,
            length: Duration(milliseconds: jsonInt(item['length']) ?? 0),
            size: jsonInt(item['size']) ?? 0,
          ),
    ];
    final firstUrl = videos.firstOrNull?.url ?? audios.firstOrNull?.url ?? segments.firstOrNull?.url;
    final deadline = jsonInt(Uri.tryParse(firstUrl ?? '')?.queryParameters['deadline']);
    return VodStreams(
      quality: jsonInt(data['quality']) ?? 0,
      qualities: qualities,
      duration: Duration(milliseconds: jsonInt(data['timelength']) ?? 0),
      videos: videos,
      audios: audios,
      dolbyAudio: _rendition(list(object(dash?['dolby'])?['audio']).firstOrNull),
      flacAudio: _rendition(object(dash?['flac'])?['audio']),
      segments: segments,
      isPreview: jsonInt(data['is_preview']) == 1,
      needsVip: jsonInt(data['status']) == 13 || jsonInt(data['error_code']) == -10403,
      headers: headers,
      expiresAt: deadline == null || deadline <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(deadline * 1000, isUtc: true),
    );
  }

  static VodRendition? _rendition(Object? value) {
    final json = object(value);
    final url = jsonString(json?['baseUrl']) ?? jsonString(json?['base_url']);
    if (json == null || url == null) return null;
    return VodRendition(
      id: jsonInt(json['id']) ?? 0,
      url: url,
      backupUrls: [for (final backup in list(json['backupUrl'] ?? json['backup_url'])) ?jsonString(backup)],
      codecs: jsonString(json['codecs']) ?? '',
      bandwidth: jsonInt(json['bandwidth']) ?? 0,
      width: jsonInt(json['width']) ?? 0,
      height: jsonInt(json['height']) ?? 0,
      frameRate: jsonString(json['frameRate']) ?? jsonString(json['frame_rate']) ?? '',
    );
  }

  // Comments ------------------------------------------------------------------

  /// One comment row.
  static VodComment? comment(Object? value, {bool pinned = false}) {
    final json = object(value);
    final rpid = jsonInt(json?['rpid']);
    if (json == null || rpid == null) return null;
    final member = object(json['member']);
    return VodComment(
      rpid: rpid,
      oid: jsonInt(json['oid']) ?? 0,
      type: jsonInt(json['type']) ?? 1,
      user: VodOwner(
        mid: jsonInt(member?['mid']) ?? 0,
        name: jsonString(member?['uname']) ?? '',
        face: normalizeImageUrl(member?['avatar']),
      ),
      level: jsonInt(object(member?['level_info'])?['current_level']) ?? 0,
      text: jsonString(object(json['content'])?['message']) ?? '',
      createdAt: unixTime(json['ctime']),
      likes: jsonInt(json['like']) ?? 0,
      replyCount: jsonInt(json['rcount']) ?? 0,
      liked: jsonInt(json['action']) == 1,
      pinned: pinned,
      upLiked: object(json['up_action'])?['like'] == true,
      location: jsonString(object(json['reply_control'])?['location']) ?? '',
      replies: [for (final reply in list(json['replies'])) ?comment(reply)],
    );
  }

  /// `x/v2/reply/wbi/main`: roots, pinned comments on the first page, and
  /// the next page's `pagination_reply.next_offset`.
  static VodCommentPage comments(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'reply main', notFound: const {-404, 12002}));
    final cursor = object(data?['cursor']);
    final next = jsonString(object(cursor?['pagination_reply'])?['next_offset']);
    final isEnd = cursor?['is_end'] == true || next == null;
    return VodCommentPage(
      comments: [for (final item in list(data?['replies'])) ?comment(item)],
      pinned: [for (final item in list(data?['top_replies'])) ?comment(item, pinned: true)],
      total: jsonInt(cursor?['all_count']) ?? 0,
      nextOffset: isEnd ? null : next,
      isEnd: isEnd,
    );
  }

  /// `x/v2/reply/reply`: numbered pages of one root's replies.
  static VodPage<VodComment> replies(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'reply reply', notFound: const {-404, 12022}));
    final page = object(data?['page']);
    final number = jsonInt(page?['num']) ?? 1;
    final size = jsonInt(page?['size']) ?? 20;
    final count = jsonInt(page?['count']) ?? 0;
    return VodPage([for (final item in list(data?['replies'])) ?comment(item)], hasMore: number * size < count);
  }

  // Account and space ----------------------------------------------------------

  /// `x/polymer/web-dynamic/v1/feed/all?type=video`: video dynamics with the
  /// next `offset`.
  static VodPage<VodDynamic> dynamics(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'dynamic feed'));
    final items = <VodDynamic>[];
    for (final item in list(data?['items']).map(object).nonNulls) {
      final modules = object(item['modules']);
      final author = object(modules?['module_author']);
      final major = object(object(modules?['module_dynamic'])?['major']);
      final archive = object(major?['archive']);
      final bvid = jsonString(archive?['bvid']);
      if (archive == null || bvid == null) continue;
      final stat = object(archive['stat']);
      items.add(
        VodDynamic(
          id: jsonString(item['id_str']) ?? '',
          archive: VodArchive(
            bvid: bvid,
            aid: jsonInt(archive['aid']) ?? 0,
            title: jsonString(archive['title']) ?? '',
            cover: normalizeImageUrl(archive['cover']),
            owner: VodOwner(
              mid: jsonInt(author?['mid']) ?? 0,
              name: jsonString(author?['name']) ?? '',
              face: normalizeImageUrl(author?['face']),
            ),
            duration: clockDuration(jsonString(archive['duration_text']) ?? ''),
            stat: VodStat(
              views: parseChineseCount(stat?['play']) ?? 0,
              danmaku: parseChineseCount(stat?['danmaku']) ?? 0,
            ),
            description: jsonString(archive['desc']) ?? '',
          ),
          publishedAt: unixTime(author?['pub_ts']),
          publishedLabel: jsonString(author?['pub_time']) ?? '',
        ),
      );
    }
    final offset = jsonString(data?['offset']);
    return VodPage(items, hasMore: data?['has_more'] == true && offset != null, cursor: offset);
  }

  /// `x/space/wbi/acc/info` with `x/relation/stat` (and the relation when
  /// signed in).
  static VodUserSpace userSpace(String info, {String? stat, int infoStatus = 200, int statStatus = 200}) {
    final data = object(VodParse.data(info, status: infoStatus, what: 'acc info', notFound: const {-404, -400}));
    final counts = stat == null ? null : object(VodParse.data(stat, status: statStatus, what: 'relation stat'));
    return VodUserSpace(
      owner: VodOwner(
        mid: jsonInt(data?['mid']) ?? 0,
        name: jsonString(data?['name']) ?? '',
        face: normalizeImageUrl(data?['face']),
      ),
      sign: jsonString(data?['sign']) ?? '',
      level: jsonInt(data?['level']) ?? 0,
      followers: jsonInt(counts?['follower']) ?? 0,
      following: jsonInt(counts?['following']) ?? 0,
      isFollowed: data?['is_followed'] == true,
      liveRoomId: jsonInt(object(data?['live_room'])?['roomid']) ?? 0,
    );
  }

  /// `x/relation/stat`: followers and followings.
  static ({int followers, int following}) relationStat(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'relation stat'));
    return (followers: jsonInt(data?['follower']) ?? 0, following: jsonInt(data?['following']) ?? 0);
  }

  /// `x/space/wbi/arc/search`: an uploader's videos.
  static VodPage<VodArchive> uploads(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'arc search'));
    final page = object(data?['page']);
    final rows = [
      for (final item in list(object(data?['list'])?['vlist']).map(object).nonNulls)
        if (jsonString(item['bvid']) case final String bvid)
          VodArchive(
            bvid: bvid,
            aid: jsonInt(item['aid']) ?? 0,
            title: jsonString(item['title']) ?? '',
            cover: normalizeImageUrl(item['pic']),
            owner: VodOwner(mid: jsonInt(item['mid']) ?? 0, name: jsonString(item['author']) ?? ''),
            duration: clockDuration(jsonString(item['length']) ?? ''),
            stat: VodStat(views: jsonInt(item['play']) ?? 0, danmaku: jsonInt(item['video_review']) ?? 0),
            typeId: jsonInt(item['typeid']) ?? 0,
            description: jsonString(item['description']) ?? '',
            publishedAt: unixTime(item['created']),
          ),
    ];
    final number = jsonInt(page?['pn']) ?? 1;
    final size = jsonInt(page?['ps']) ?? rows.length;
    return VodPage(rows, hasMore: number * size < (jsonInt(page?['count']) ?? 0));
  }

  /// `x/polymer/web-space/seasons_series_list`: the uploader's seasons and
  /// series (music mode's uploader playlists).
  static VodPage<VodUpCollection> collections(String body, {required int mid, int status = 200}) {
    final lists = object(object(VodParse.data(body, status: status, what: 'seasons series'))?['items_lists']);
    VodUpCollection? read(Object? value, {required bool series}) {
      final meta = object(object(value)?['meta']);
      final id = jsonInt(meta?[series ? 'series_id' : 'season_id']);
      if (meta == null || id == null) return null;
      return VodUpCollection(
        id: id,
        isSeries: series,
        mid: jsonInt(meta['mid']) ?? mid,
        title: jsonString(meta['name']) ?? '',
        cover: normalizeImageUrl(meta['cover']),
        total: jsonInt(meta['total']) ?? 0,
        description: jsonString(meta['description']) ?? '',
      );
    }

    final page = object(lists?['page']);
    final items = [
      for (final item in list(lists?['seasons_list'])) ?read(item, series: false),
      for (final item in list(lists?['series_list'])) ?read(item, series: true),
    ];
    final number = jsonInt(page?['page_num']) ?? 1;
    final size = jsonInt(page?['page_size']) ?? 10;
    return VodPage(items, hasMore: number * size < (jsonInt(page?['total']) ?? 0));
  }

  /// `seasons_archives_list` and `x/series/archives`: the collection's
  /// archives.
  static VodPage<VodArchive> collectionArchives(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'collection archives'));
    final page = object(data?['page']);
    final rows = [
      for (final item in list(data?['archives']).map(object).nonNulls)
        if (jsonString(item['bvid']) case final String bvid)
          VodArchive(
            bvid: bvid,
            aid: jsonInt(item['aid']) ?? 0,
            title: jsonString(item['title']) ?? '',
            cover: normalizeImageUrl(item['pic']),
            duration: Duration(seconds: jsonInt(item['duration']) ?? 0),
            stat: VodStat(views: jsonInt(object(item['stat'])?['view']) ?? 0),
            publishedAt: unixTime(item['pubdate']),
          ),
    ];
    final number = jsonInt(page?['page_num'] ?? page?['num']) ?? 1;
    final size = jsonInt(page?['page_size'] ?? page?['size']) ?? rows.length;
    return VodPage(rows, hasMore: number * size < (jsonInt(page?['total']) ?? 0));
  }

  /// `x/v3/fav/folder/created/list-all` and `collected/list`.
  static List<VodFavFolder> favFolders(String body, {int status = 200}) => [
    for (final item in list(
      object(VodParse.data(body, status: status, what: 'fav folders'))?['list'],
    ).map(object).nonNulls)
      if (jsonInt(item['id']) case final int id)
        VodFavFolder(
          id: id,
          title: jsonString(item['title']) ?? '',
          mediaCount: jsonInt(item['media_count']) ?? 0,
          cover: normalizeImageUrl(item['cover'] is Map ? (item['cover']! as Map)['url'] : item['cover']),
          isPublic: ((jsonInt(item['attr']) ?? 0) & 1) == 0,
          ownerMid: jsonInt(item['mid']) ?? jsonInt(object(item['upper'])?['mid']) ?? 0,
          containsTarget: jsonInt(item['fav_state']) == 1,
        ),
  ];

  /// `x/v3/fav/resource/list`: a folder's videos (`attr` bit 0 marks a
  /// deleted one).
  static VodPage<VodFavItem> favItems(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'fav resources'));
    final items = [
      for (final item in list(data?['medias']).map(object).nonNulls)
        if (jsonString(item['bvid']) case final String bvid)
          VodFavItem(
            archive: VodArchive(
              bvid: bvid,
              aid: jsonInt(item['id']) ?? 0,
              title: jsonString(item['title']) ?? '',
              cover: normalizeImageUrl(item['cover']),
              owner: VodOwner(
                mid: jsonInt(object(item['upper'])?['mid']) ?? 0,
                name: jsonString(object(item['upper'])?['name']) ?? '',
                face: normalizeImageUrl(object(item['upper'])?['face']),
              ),
              duration: Duration(seconds: jsonInt(item['duration']) ?? 0),
              stat: VodStat(
                views: jsonInt(object(item['cnt_info'])?['play']) ?? 0,
                danmaku: jsonInt(object(item['cnt_info'])?['danmaku']) ?? 0,
              ),
              cid: jsonInt(object(item['ugc'])?['first_cid']) ?? 0,
              partCount: jsonInt(item['page']) ?? 1,
            ),
            invalid: ((jsonInt(item['attr']) ?? 0) & 1) == 1 || jsonString(item['title']) == '已失效视频',
            favoritedAt: unixTime(item['fav_time']),
          ),
    ];
    return VodPage(items, hasMore: data?['has_more'] == true);
  }

  /// `x/web-interface/history/cursor`: rows and the next cursor
  /// (`max:view_at:business`).
  static VodPage<VodHistoryEntry> history(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'history'));
    final rows = <VodHistoryEntry>[];
    for (final item in list(data?['list']).map(object).nonNulls) {
      final history = object(item['history']);
      final progress = jsonInt(item['progress']) ?? 0;
      rows.add(
        VodHistoryEntry(
          archive: VodArchive(
            bvid: jsonString(history?['bvid']) ?? '',
            aid: jsonInt(history?['oid']) ?? 0,
            title: jsonString(item['show_title']) ?? jsonString(item['title']) ?? '',
            cover: normalizeImageUrl(item['cover'] ?? list(item['covers']).firstOrNull),
            owner: VodOwner(
              mid: jsonInt(item['author_mid']) ?? 0,
              name: jsonString(item['author_name']) ?? '',
              face: normalizeImageUrl(item['author_face']),
            ),
            duration: Duration(seconds: jsonInt(item['duration']) ?? 0),
            cid: jsonInt(history?['cid']) ?? 0,
            partCount: jsonInt(item['videos']) ?? 1,
          ),
          business: jsonString(history?['business']) ?? 'archive',
          cid: jsonInt(history?['cid']) ?? 0,
          page: jsonInt(history?['page']) ?? 1,
          progress: Duration(seconds: progress < 0 ? 0 : progress),
          finished: progress < 0,
          viewedAt: unixTime(item['view_at']),
          epId: jsonInt(history?['epid']) ?? 0,
          seasonId: jsonInt(item['kid']) != null && jsonString(history?['business']) == 'pgc'
              ? jsonInt(item['kid'])!
              : 0,
        ),
      );
    }
    final cursor = object(data?['cursor']);
    final max = jsonInt(cursor?['max']) ?? 0;
    final viewAt = jsonInt(cursor?['view_at']) ?? 0;
    final hasMore = rows.isNotEmpty && max > 0;
    return VodPage(
      rows,
      hasMore: hasMore,
      cursor: hasMore ? '$max:$viewAt:${jsonString(cursor?['business']) ?? ''}' : null,
    );
  }

  /// `x/v2/history/toview`: watch later.
  static List<VodArchive> toView(String body, {int status = 200}) => [
    for (final item in list(object(VodParse.data(body, status: status, what: 'toview'))?['list'])) ?archive(item),
  ];

  // PGC -----------------------------------------------------------------------

  /// `pgc/web/timeline`: the days around today.
  static List<PgcTimelineDay> timeline(String body, {int status = 200}) {
    final result = VodParse.data(body, status: status, what: 'pgc timeline');
    return [
      for (final day in list(result).map(object).nonNulls)
        PgcTimelineDay(
          date: unixTime(day['date_ts']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          dayOfWeek: jsonInt(day['day_of_week']) ?? 0,
          isToday: jsonInt(day['is_today']) == 1,
          episodes: [
            for (final item in list(day['episodes']).map(object).nonNulls)
              PgcTimelineEntry(
                seasonId: jsonInt(item['season_id']) ?? 0,
                episodeId: jsonInt(item['episode_id']) ?? 0,
                title: jsonString(item['title']) ?? '',
                cover: normalizeImageUrl(item['cover']),
                index: jsonString(item['pub_index']) ?? '',
                time: jsonString(item['pub_time']) ?? '',
                releasedAt: unixTime(item['pub_ts']),
                published: jsonInt(item['published']) == 1,
                delayed: jsonInt(item['delay']) == 1,
                delayReason: jsonString(item['delay_reason']) ?? '',
              ),
          ],
        ),
    ];
  }

  /// One season card of the index and follow lists.
  static PgcCard? card(Object? value) {
    final json = object(value);
    final id = jsonInt(json?['season_id']);
    if (json == null || id == null) return null;
    final badge = jsonString(json['badge']) ?? jsonString(object(json['badge_info'])?['text']) ?? '';
    return PgcCard(
      seasonId: id,
      mediaId: jsonInt(json['media_id']) ?? 0,
      title: plain(json['title'] ?? json['season_title']),
      cover: normalizeImageUrl(json['cover']),
      badge: badge,
      subtitle: jsonString(json['subTitle']) ?? jsonString(json['subtitle']) ?? '',
      indexShow: jsonString(json['index_show']) ?? jsonString(object(json['new_ep'])?['index_show']) ?? '',
      score: jsonString(json['score']) ?? jsonString(object(json['rating'])?['score']) ?? '',
      isFinished: jsonInt(json['is_finish']) == 1,
      firstEpId: jsonInt(object(json['first_ep'])?['ep_id']) ?? 0,
      type: jsonInt(json['season_type']) ?? 0,
      needsVip: jsonInt(json['season_status']) == 13 || badge.contains('会员'),
    );
  }

  /// `pgc/season/index/result`: one page of the index.
  static VodPage<PgcCard> index(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'pgc index'));
    return VodPage([for (final item in list(data?['list'])) ?card(item)], hasMore: jsonInt(data?['has_next']) == 1);
  }

  /// `x/space/bangumi/follow/list`: followed seasons.
  static VodPage<PgcCard> followedSeasons(String body, {int status = 200}) {
    final data = object(VodParse.data(body, status: status, what: 'bangumi follow'));
    final number = jsonInt(data?['pn']) ?? 1;
    final size = jsonInt(data?['ps']) ?? 0;
    return VodPage([
      for (final item in list(data?['list'])) ?card(item),
    ], hasMore: number * size < (jsonInt(data?['total']) ?? 0));
  }

  /// `pgc/view/web/season`: the season with its episodes and extras.
  static PgcSeason season(String body, {int status = 200}) {
    final result = object(VodParse.data(body, status: status, what: 'pgc season', notFound: const {-404, -10403}));
    final id = jsonInt(result?['season_id']);
    if (result == null || id == null) throw ApiChanged(vodSite, 'pgc season: no season_id (${snippet(body)})');
    final rating = object(result['rating']);
    return PgcSeason(
      seasonId: id,
      mediaId: jsonInt(result['media_id']) ?? 0,
      title: jsonString(result['season_title']) ?? jsonString(result['title']) ?? '',
      cover: normalizeImageUrl(result['cover']),
      evaluate: jsonString(result['evaluate']) ?? '',
      score: switch (rating?['score']) {
        final num score => score.toDouble(),
        final String text => double.tryParse(text) ?? 0,
        _ => 0,
      },
      scoreCount: jsonInt(rating?['count']) ?? 0,
      styles: [
        for (final style in list(result['styles']))
          if (style is Map ? jsonString(style['name']) : jsonString(style) case final String name) name,
      ],
      publishTime: jsonString(object(result['publish'])?['pub_time']) ?? '',
      isFinished: jsonInt(object(result['publish'])?['is_finish']) == 1,
      status: jsonInt(result['status']) ?? 2,
      paymentTip: jsonString(object(result['payment'])?['tip']) ?? '',
      episodes: [for (final item in list(result['episodes'])) ?episode(item)],
      extras: [
        for (final section in list(result['section']).map(object).nonNulls)
          for (final item in list(section['episodes'])) ?episode(item),
      ],
      relatedSeasons: [for (final item in list(result['seasons'])) ?card(item)],
    );
  }

  /// One episode of a season.
  static PgcEpisode? episode(Object? value) {
    final json = object(value);
    final id = jsonInt(json?['ep_id']) ?? jsonInt(json?['id']);
    if (json == null || id == null) return null;
    final skip = object(json['skip']);
    ({Duration start, Duration end})? range(Object? value) {
      final range = object(value);
      final start = jsonInt(range?['start']) ?? 0;
      final end = jsonInt(range?['end']) ?? 0;
      return end > start ? (start: Duration(seconds: start), end: Duration(seconds: end)) : null;
    }

    return PgcEpisode(
      epId: id,
      cid: jsonInt(json['cid']) ?? 0,
      aid: jsonInt(json['aid']) ?? 0,
      bvid: jsonString(json['bvid']) ?? '',
      title: jsonString(json['title']) ?? '',
      longTitle: jsonString(json['long_title']) ?? '',
      showTitle: jsonString(json['show_title']) ?? '',
      cover: normalizeImageUrl(json['cover']),
      duration: Duration(milliseconds: jsonInt(json['duration']) ?? 0),
      badge: jsonString(json['badge']) ?? jsonString(object(json['badge_info'])?['text']) ?? '',
      status: jsonInt(json['status']) ?? 2,
      releasedAt: unixTime(json['pub_time']),
      opening: range(skip?['op']),
      ending: range(skip?['ed']),
    );
  }

  // Helpers ---------------------------------------------------------------------

  /// [value] as a JSON object, or null.
  static Map<String, dynamic>? object(Object? value) => value is Map<String, dynamic> ? value : null;

  /// [value] as a JSON array, or empty.
  static List<Object?> list(Object? value) => value is List ? value.cast<Object?>() : const [];

  static final RegExp _tag = RegExp('<[^>]*>');

  /// Text without the `<em class="keyword">` highlights, entities decoded.
  static String plain(Object? value) => decodeHtmlEntities((jsonString(value) ?? '').replaceAll(_tag, ''));

  /// Unix seconds as a UTC time; null for 0 and below.
  static DateTime? unixTime(Object? value) => switch (jsonInt(value)) {
    final int seconds when seconds > 0 => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    _ => null,
  };

  /// `mm:ss` or `hh:mm:ss` as a duration; zero for anything else.
  static Duration clockDuration(String text) {
    final parts = text.trim().split(':').map(int.tryParse).toList();
    if (parts.any((part) => part == null || part < 0)) return Duration.zero;
    return switch (parts) {
      [final int m, final int s] => Duration(minutes: m, seconds: s),
      [final int h, final int m, final int s] => Duration(hours: h, minutes: m, seconds: s),
      _ => Duration.zero,
    };
  }
}
