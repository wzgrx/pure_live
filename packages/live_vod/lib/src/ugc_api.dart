import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_vod/src/client.dart';
import 'package:live_vod/src/danmaku.dart';
import 'package:live_vod/src/models.dart';
import 'package:live_vod/src/parse.dart';
import 'package:live_vod/src/streams.dart';

const String _api = 'api.bilibili.com';
const String _search = 'https://search.bilibili.com/';

/// Video (UGC) endpoints: catalogs, detail, streams, subtitles, comments,
/// dynamics, uploader spaces, follows, favourites, watch later, history and
/// search (pure_live_TV `b9d2f739` `bilibili_ugc_api.dart`,
/// `bilibili_music_api.dart`, `bilibili_danmaku_api.dart`).
///
/// Reads work signed out unless noted; personal lists and every write throw
/// `NeedsLogin` before sending anything when no cookie is stored.
final class BilibiliUgcApi {
  /// Creates the API over [client].
  const new(this.client);

  /// Request plumbing.
  final BilibiliVodClient client;

  // Catalogs ------------------------------------------------------------------

  /// Popular now (`popular`), 20 a page.
  Future<VodPage<VodArchive>> popular({int page = 1, int pageSize = 20}) async {
    final r = await client.get(Uri.https(_api, '/x/web-interface/popular'), query: {'pn': page, 'ps': pageSize});
    return VodParse.popular(r.text, status: r.status);
  }

  /// A partition's ranking (`ranking/v2`; [rid] 0 = all, 3 = music).
  Future<List<VodArchive>> ranking({int rid = 0}) async {
    final r = await client.get(Uri.https(_api, '/x/web-interface/ranking/v2'), query: {'rid': rid, 'type': 'all'});
    return VodParse.ranking(r.text, status: r.status);
  }

  /// The home feed (`wbi/index/top/feed/rcmd`, WBI): personal when signed
  /// in, generic otherwise. [page] is the refresh index.
  Future<List<VodArchive>> recommended({int page = 1, int pageSize = 12}) =>
      client.signed(Uri.https(_api, '/x/web-interface/wbi/index/top/feed/rcmd'), {
        'fresh_type': '4',
        'ps': '$pageSize',
        'fresh_idx': '$page',
        'fresh_idx_1h': '$page',
        'brush': '$page',
        'web_location': '1430650',
      }, (r) => VodParse.recommended(r.text, status: r.status));

  /// Archives related to [bvid] (`archive/related`).
  Future<List<VodArchive>> related(String bvid) async {
    final r = await client.get(Uri.https(_api, '/x/web-interface/archive/related'), query: {'bvid': bvid});
    return VodParse.related(r.text, status: r.status);
  }

  /// The archive with every part (`view`).
  Future<VodArchive> detail(String bvid) async {
    final r = await client.get(Uri.https(_api, '/x/web-interface/view'), query: {'bvid': bvid});
    return VodParse.view(r.text, status: r.status);
  }

  // Streams -------------------------------------------------------------------

  /// Streams of one part. DASH (`fnval=4048`: DASH, HDR, 4K, Dolby, 8K, AV1)
  /// carries every quality and audio track the account may play; guests
  /// get 480P at most. [mp4] asks for the muxed `durl` file instead
  /// (`platform=html5`), the route the TV client kept.
  Future<VodStreams> streams({required String bvid, required int cid, int qn = 0, bool mp4 = false}) async {
    final page = 'https://www.bilibili.com/video/$bvid/';
    final r = await client.stream(
      Uri.https(_api, '/x/player/playurl'),
      query: mp4
          ? {
              'bvid': bvid,
              'cid': cid,
              'qn': qn == 0 ? 80 : qn,
              'fnval': 0,
              'fnver': 0,
              'fourk': 1,
              'platform': 'html5',
              'high_quality': 1,
            }
          : {'bvid': bvid, 'cid': cid, 'qn': qn, 'fnval': 4048, 'fnver': 0, 'fourk': 1},
      referer: page,
    );
    return VodParse.streams(r.text, headers: client.mediaHeaders(page), status: r.status);
  }

  /// Subtitles, BGM, resume point and viewers of one part (`player/wbi/v2`).
  /// Guests get no subtitles.
  Future<VodPlayerInfo> playerInfo({required String bvid, required int cid, int aid = 0}) => client.signed(
    Uri.https(_api, '/x/player/wbi/v2'),
    {if (aid > 0) 'aid': '$aid', 'bvid': bvid, 'cid': '$cid'},
    (r) => VodParse.playerInfo(r.text, status: r.status),
  );

  /// The cues of [track].
  Future<List<VodSubtitleCue>> subtitleCues(VodSubtitleTrack track) async {
    final r = await client.file(Uri.parse(track.url));
    if (!r.isSuccess) throw ApiChanged(vodSite, 'subtitle: HTTP ${r.status}');
    return VodParse.subtitleCues(r.text);
  }

  // Danmaku -------------------------------------------------------------------

  /// How many 6-minute segments [cid] has (`dm/web/view`, protobuf).
  Future<int> danmakuSegments({required int aid, required int cid, Duration duration = Duration.zero}) async {
    final r = await client.get(Uri.https(_api, '/x/v2/dm/web/view'), query: {'type': 1, 'oid': cid, 'pid': aid});
    if (!r.isSuccess) throw NetworkFailure(vodSite, 'dm view: HTTP ${r.status}');
    return VodDanmakuParse.view(r.bytes, duration: duration).segments;
  }

  /// One 6-minute segment, 1-based (`dm/wbi/web/seg.so`, WBI, protobuf).
  Future<List<VodDanmaku>> danmakuSegment({required int aid, required int cid, required int segment}) => client.signed(
    Uri.https(_api, '/x/v2/dm/wbi/web/seg.so'),
    {'type': '1', 'oid': '$cid', 'pid': '$aid', 'segment_index': '$segment'},
    (r) {
      if (r.status == 412) throw const RateLimited(vodSite, detail: 'dm seg: HTTP 412');
      if (!r.isSuccess) throw NetworkFailure(vodSite, 'dm seg: HTTP ${r.status}');
      // A JSON body is an error envelope (-352 and friends).
      if (r.bytes.isNotEmpty && r.bytes.first == 0x7B) VodParse.data(r.text, status: r.status, what: 'dm seg');
      return VodDanmakuParse.segment(r.bytes);
    },
  );

  /// The whole XML file (`comment.bilibili.com/{cid}.xml`): the fallback
  /// when the segment endpoint fails. It holds at most the newest
  /// `maxlimit` danmaku.
  Future<List<VodDanmaku>> danmakuXml(int cid) async {
    final r = await client.file(Uri.https('comment.bilibili.com', '/$cid.xml'));
    if (!r.isSuccess) throw NetworkFailure(vodSite, 'dm xml: HTTP ${r.status}');
    return VodDanmakuParse.xml(r.text);
  }

  /// Sends a danmaku at [progress] (`dm/post`), signed in only.
  Future<void> sendDanmaku({
    required int aid,
    required int cid,
    required String text,
    Duration progress = Duration.zero,
    int mode = 1,
    int color = 0xFFFFFF,
    int fontSize = 25,
  }) => client.post(Uri.https(_api, '/x/v2/dm/post'), {
    'type': '1',
    'oid': '$cid',
    'aid': '$aid',
    'msg': text,
    'progress': '${progress.inMilliseconds}',
    'mode': '$mode',
    'color': '$color',
    'fontsize': '$fontSize',
    'pool': '0',
    'rnd': '${DateTime.now().microsecondsSinceEpoch}',
  }, what: 'dm post');

  // Comments ------------------------------------------------------------------

  /// Root comments of [oid] ([type] 1 = video), hot ([hot]) or newest
  /// first. Pass the previous page's [VodCommentPage.nextOffset] as
  /// [offset]; null asks for the first page. Guests get the first few hot
  /// comments only (no next offset).
  Future<VodCommentPage> comments({required int oid, int type = 1, bool hot = true, String? offset}) =>
      client.signed(Uri.https(_api, '/x/v2/reply/wbi/main'), {
        'oid': '$oid',
        'type': '$type',
        'mode': hot ? '3' : '2',
        'pagination_str': jsonEncode({'offset': offset ?? ''}),
        'plat': '1',
        'web_location': '1315875',
      }, (r) => VodParse.comments(r.text, status: r.status));

  /// Replies under [root] (`reply/reply`), numbered pages of 20.
  Future<VodPage<VodComment>> replies({required int oid, required int root, int type = 1, int page = 1}) async {
    final r = await client.get(
      Uri.https(_api, '/x/v2/reply/reply'),
      query: {'oid': oid, 'type': type, 'root': root, 'pn': page, 'ps': 20},
    );
    return VodParse.replies(r.text, status: r.status);
  }

  /// Likes or un-likes a comment.
  Future<void> likeComment({required int oid, required int rpid, required bool like, int type = 1}) => client.post(
    Uri.https(_api, '/x/v2/reply/action'),
    {'oid': '$oid', 'type': '$type', 'rpid': '$rpid', 'action': like ? '1' : '0'},
    what: 'reply action',
  );

  /// Posts a comment, or a reply when [root] (and [parent]) are given.
  Future<void> addComment({required int oid, required String text, int type = 1, int root = 0, int parent = 0}) =>
      client.post(Uri.https(_api, '/x/v2/reply/add'), {
        'oid': '$oid',
        'type': '$type',
        'message': text,
        'plat': '1',
        if (root > 0) 'root': '$root',
        if (parent > 0) 'parent': '$parent',
      }, what: 'reply add');

  // Dynamics, spaces, follows -------------------------------------------------------

  /// Video dynamics of followed uploaders, signed in only; pass the previous
  /// page's cursor as [offset].
  Future<VodPage<VodDynamic>> dynamics({String? offset}) async {
    client.requireLogin('dynamic feed');
    final r = await client.get(
      Uri.https(_api, '/x/polymer/web-dynamic/v1/feed/all'),
      query: {'type': 'video', 'offset': ?offset},
    );
    return VodParse.dynamics(r.text, status: r.status);
  }

  /// An uploader's space header (`space/wbi/acc/info`, WBI) with follower
  /// counts. Guests get -352 (`RiskControl`) from `acc/info` since 2026.
  Future<VodUserSpace> userSpace(int mid) async {
    final info = await client.signed(
      Uri.https(_api, '/x/space/wbi/acc/info'),
      {'mid': '$mid'},
      (r) => r,
      referer: 'https://space.bilibili.com/$mid/',
    );
    final stat = await client.get(Uri.https(_api, '/x/relation/stat'), query: {'vmid': mid});
    return VodParse.userSpace(info.text, stat: stat.text, infoStatus: info.status, statStatus: stat.status);
  }

  /// An uploader's followers and followings (`relation/stat`); guests too.
  Future<({int followers, int following})> relationStat(int mid) async {
    final r = await client.get(Uri.https(_api, '/x/relation/stat'), query: {'vmid': mid});
    return VodParse.relationStat(r.text, status: r.status);
  }

  /// An uploader's videos (`space/wbi/arc/search`, WBI; -352 for guests).
  /// [order]: `pubdate`, `click`, `stow`.
  Future<VodPage<VodArchive>> uploads(int mid, {int page = 1, int pageSize = 30, String order = 'pubdate'}) =>
      client.signed(
        Uri.https(_api, '/x/space/wbi/arc/search'),
        {'mid': '$mid', 'pn': '$page', 'ps': '$pageSize', 'order': order, 'index': '1'},
        (r) => VodParse.uploads(r.text, status: r.status),
        referer: 'https://space.bilibili.com/$mid/',
      );

  /// Follows or unfollows an uploader (`relation/modify`; `re_src` 11 is
  /// required or the change is silently dropped, per the TV client).
  Future<void> setFollowing(int mid, {required bool follow}) => client.post(Uri.https(_api, '/x/relation/modify'), {
    'fid': '$mid',
    'act': follow ? '1' : '2',
    're_src': '11',
  }, what: 'relation modify');

  /// The signed-in user's followings, signed in only.
  Future<VodPage<VodOwner>> followings({int page = 1, int pageSize = 24}) async {
    client.requireLogin('followings');
    final r = await client.get(
      Uri.https(_api, '/x/relation/followings'),
      query: {'vmid': client.myMid, 'pn': page, 'ps': pageSize},
    );
    final data = VodParse.object(VodParse.data(r.text, status: r.status, what: 'followings'));
    final rows = [
      for (final item in VodParse.list(data?['list']).map(VodParse.object).nonNulls)
        VodOwner(
          mid: jsonInt(item['mid']) ?? 0,
          name: jsonString(item['uname']) ?? '',
          face: normalizeImageUrl(item['face']),
        ),
    ];
    return VodPage(rows, hasMore: page * pageSize < (jsonInt(data?['total']) ?? 0));
  }

  // Interactions ---------------------------------------------------------------

  /// Likes or un-likes an archive.
  Future<void> setLike(int aid, {required bool like}) => client.post(Uri.https(_api, '/x/web-interface/archive/like'), {
    'aid': '$aid',
    'like': like ? '1' : '2',
  }, what: 'archive like');

  /// Gives [multiply] (1 or 2) coins, optionally liking too.
  Future<void> addCoin(int aid, {int multiply = 1, bool alsoLike = false}) => client.post(
    Uri.https(_api, '/x/web-interface/coin/add'),
    {'aid': '$aid', 'multiply': '${multiply.clamp(1, 2)}', 'select_like': alsoLike ? '1' : '0'},
    what: 'coin add',
  );

  /// Like, coin and favourite at once.
  Future<void> triple(int aid) =>
      client.post(Uri.https(_api, '/x/web-interface/archive/like/triple'), {'aid': '$aid'}, what: 'like triple');

  /// Whether the signed-in user liked, coined, favourited [bvid]
  /// (`archive/relation`).
  Future<({bool liked, int coins, bool favorited})> relation({required String bvid}) async {
    client.requireLogin('archive relation');
    final r = await client.get(Uri.https(_api, '/x/web-interface/archive/relation'), query: {'bvid': bvid});
    final data = VodParse.object(VodParse.data(r.text, status: r.status, what: 'archive relation'));
    return (liked: data?['like'] == true, coins: jsonInt(data?['coin']) ?? 0, favorited: data?['favorite'] == true);
  }

  // Favourites ------------------------------------------------------------------

  /// The user's folders; with [aid], [VodFavFolder.containsTarget] says
  /// which hold it. Signed in only.
  Future<List<VodFavFolder>> favFolders({int aid = 0}) async {
    client.requireLogin('fav folders');
    final r = await client.get(
      Uri.https(_api, '/x/v3/fav/folder/created/list-all'),
      query: {'up_mid': client.myMid, 'type': 2, if (aid > 0) 'rid': aid},
    );
    return VodParse.favFolders(r.text, status: r.status);
  }

  /// Folders the user collected from others. Signed in only.
  Future<List<VodFavFolder>> collectedFolders({int page = 1, int pageSize = 20}) async {
    client.requireLogin('collected folders');
    final r = await client.get(
      Uri.https(_api, '/x/v3/fav/folder/collected/list'),
      query: {'up_mid': client.myMid, 'pn': page, 'ps': pageSize, 'platform': 'web'},
    );
    return VodParse.favFolders(r.text, status: r.status);
  }

  /// One folder's videos (public folders work signed out).
  Future<VodPage<VodFavItem>> favItems(int mediaId, {int page = 1, int pageSize = 20}) async {
    final r = await client.get(
      Uri.https(_api, '/x/v3/fav/resource/list'),
      query: {
        'media_id': mediaId,
        'pn': page,
        'ps': pageSize,
        'order': 'mtime',
        'type': 0,
        'tid': 0,
        'platform': 'web',
      },
    );
    return VodParse.favItems(r.text, status: r.status);
  }

  /// Adds [aid] to [add] folders and removes it from [remove].
  Future<void> setFavorites(int aid, {List<int> add = const [], List<int> remove = const []}) => client.post(
    Uri.https(_api, '/x/v3/fav/resource/deal'),
    {'rid': '$aid', 'type': '2', 'add_media_ids': add.join(','), 'del_media_ids': remove.join(',')},
    what: 'fav deal',
  );

  /// Creates a folder.
  Future<void> createFolder(String title, {bool public = true}) => client.post(
    Uri.https(_api, '/x/v3/fav/folder/add'),
    {'title': title, 'privacy': public ? '0' : '1'},
    what: 'fav folder add',
  );

  // Watch later and history ------------------------------------------------------

  /// Watch later. Signed in only.
  Future<List<VodArchive>> toView() async {
    client.requireLogin('toview');
    final r = await client.get(Uri.https(_api, '/x/v2/history/toview'));
    return VodParse.toView(r.text, status: r.status);
  }

  /// Adds to watch later.
  Future<void> addToView(int aid) =>
      client.post(Uri.https(_api, '/x/v2/history/toview/add'), {'aid': '$aid'}, what: 'toview add');

  /// Removes from watch later.
  Future<void> removeToView(int aid) =>
      client.post(Uri.https(_api, '/x/v2/history/toview/del'), {'aid': '$aid'}, what: 'toview del');

  /// Cloud history, newest first; pass the previous page's cursor. Signed in
  /// only. [business] filters (`archive`, `pgc`), '' = all.
  Future<VodPage<VodHistoryEntry>> history({String? cursor, String business = ''}) async {
    client.requireLogin('history');
    final parts = (cursor ?? '0:0:').split(':');
    final r = await client.get(
      Uri.https(_api, '/x/web-interface/history/cursor'),
      query: {
        'type': business.isEmpty ? 'all' : business,
        'max': parts.first,
        'view_at': parts.length > 1 ? parts[1] : '0',
        'business': parts.length > 2 ? parts[2] : '',
        'ps': 20,
      },
    );
    return VodParse.history(r.text, status: r.status);
  }

  /// Reports watch progress (`history/report`) so the cloud history and the
  /// resume point follow the player. Signed in only; a guest call throws
  /// `NeedsLogin` without a request.
  Future<void> reportProgress({required int aid, required int cid, required Duration progress, int epId = 0}) =>
      client.post(Uri.https(_api, '/x/v2/history/report'), {
        'aid': '$aid',
        'cid': '$cid',
        'progress': '${progress.inSeconds}',
        'platform': 'web',
        if (epId > 0) 'epid': '$epId',
      }, what: 'history report');

  /// Deletes history rows (`kid` = `archive_{aid}` or `pgc_{seasonId}`).
  Future<void> deleteHistory(List<String> kids) =>
      client.post(Uri.https(_api, '/x/v2/history/delete'), {'kid': kids.join(',')}, what: 'history delete');

  // Search --------------------------------------------------------------------

  Future<T> _searchType<T>(String type, String keyword, int page, T Function(String body, int status) parse) =>
      client.signed(
        Uri.https(_api, '/x/web-interface/wbi/search/type'),
        {'search_type': type, 'keyword': keyword.trim(), 'page': '$page', 'page_size': '20', 'order': 'totalrank'},
        (r) => parse(r.text, r.status),
        referer: _search,
      );

  /// Video search.
  Future<VodPage<VodArchive>> searchVideos(String keyword, {int page = 1}) async => keyword.trim().isEmpty
      ? const VodPage([])
      : await _searchType('video', keyword, page, (body, status) => VodParse.searchVideos(body, status: status));

  /// User search.
  Future<VodPage<VodSearchUser>> searchUsers(String keyword, {int page = 1}) async => keyword.trim().isEmpty
      ? const VodPage([])
      : await _searchType('bili_user', keyword, page, (body, status) => VodParse.searchUsers(body, status: status));

  /// Trending words (`search/square`).
  Future<List<VodHotword>> hotwords({int limit = 10}) async {
    final r = await client.get(
      Uri.https(_api, '/x/web-interface/search/square'),
      query: {'limit': limit, 'platform': 'web'},
      referer: _search,
    );
    return VodParse.hotwords(r.text, status: r.status);
  }

  /// Completions of [term] (`s.search.bilibili.com/main/suggest`); empty on
  /// any failure.
  Future<List<String>> suggestions(String term) async {
    if (term.trim().isEmpty) return const [];
    try {
      final r = await client.get(
        Uri.https('s.search.bilibili.com', '/main/suggest'),
        query: {'term': term.trim(), 'main_ver': 'v1'},
        referer: _search,
      );
      return r.isSuccess ? VodParse.suggestions(r.text) : const [];
    } on SiteError {
      return const [];
    }
  }
}
