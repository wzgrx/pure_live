import 'package:live_vod/src/client.dart';
import 'package:live_vod/src/models.dart';
import 'package:live_vod/src/parse.dart';
import 'package:live_vod/src/pgc_models.dart';
import 'package:live_vod/src/streams.dart';

const String _api = 'api.bilibili.com';

/// PGC endpoints: release timeline, index, season detail, episode streams,
/// followed seasons and search (pure_live_TV `b9d2f739`
/// `bilibili_pgc_api.dart`).
///
/// Member-only episodes are marked as they are ([PgcEpisode.needsVip],
/// [VodStreams.needsVip], [VodStreams.isPreview]); a non-member gets the
/// platform's preview (about three minutes) and nothing works around it.
final class BilibiliPgcApi {
  /// Creates the API over [client].
  const new(this.client);

  /// Request plumbing.
  final BilibiliVodClient client;

  /// Releases from [before] days ago to [after] days ahead (`pgc/web/timeline`;
  /// [type] 1 anime, 4 guochuang).
  Future<List<PgcTimelineDay>> timeline({PgcType type = PgcType.anime, int before = 6, int after = 6}) async {
    final r = await client.get(
      Uri.https(_api, '/pgc/web/timeline'),
      query: {'types': type.id, 'before': before, 'after': after},
    );
    return VodParse.timeline(r.text, status: r.status);
  }

  /// One page of the index (`pgc/season/index/result`), most followed first
  /// ([order] 3); other filters are the web page's `-1` (any).
  Future<VodPage<PgcCard>> index({
    PgcType type = PgcType.anime,
    int page = 1,
    int pageSize = 20,
    int order = 3,
    Map<String, String> filters = const {},
  }) async {
    final r = await client.get(
      Uri.https(_api, '/pgc/season/index/result'),
      query: {
        'st': type.id,
        'order': order,
        'season_version': -1,
        'spoken_language_type': -1,
        'area': -1,
        'is_finish': -1,
        'copyright': -1,
        'season_status': -1,
        'season_month': -1,
        'year': -1,
        'style_id': -1,
        'sort': 0,
        'page': page,
        'season_type': type.id,
        'pagesize': pageSize,
        'type': 1,
        ...filters,
      },
    );
    return VodParse.index(r.text, status: r.status);
  }

  /// The season by [seasonId] or by one of its episodes ([epId]).
  Future<PgcSeason> season({int? seasonId, int? epId}) async {
    final r = await client.get(
      Uri.https(_api, '/pgc/view/web/season'),
      query: {'season_id': ?seasonId, 'ep_id': ?epId},
    );
    return VodParse.season(r.text, status: r.status);
  }

  /// Streams of an episode (DASH; [mp4] for the muxed file).
  Future<VodStreams> streams({required int epId, required int cid, int qn = 0, bool mp4 = false}) async {
    final page = 'https://www.bilibili.com/bangumi/play/ep$epId';
    final r = await client.stream(
      Uri.https(_api, '/pgc/player/web/playurl'),
      query: mp4
          ? {'ep_id': epId, 'cid': cid, 'qn': qn == 0 ? 80 : qn, 'fnval': 0, 'fnver': 0, 'fourk': 1}
          : {'ep_id': epId, 'cid': cid, 'qn': qn, 'fnval': 4048, 'fnver': 0, 'fourk': 1},
      referer: page,
    );
    return VodParse.streams(r.text, headers: client.mediaHeaders(page), status: r.status);
  }

  /// Followed seasons ([type] 1 anime, 2 movies and series). Signed in only.
  Future<VodPage<PgcCard>> followed({int type = 1, int page = 1, int pageSize = 24}) async {
    client.requireLogin('bangumi follow');
    final r = await client.get(
      Uri.https(_api, '/x/space/bangumi/follow/list'),
      query: {'vmid': client.myMid, 'type': type, 'pn': page, 'ps': pageSize},
    );
    return VodParse.followedSeasons(r.text, status: r.status);
  }

  /// Follows (追番) or unfollows a season.
  Future<void> setFollowing(int seasonId, {required bool follow}) => client.post(
    Uri.https(_api, follow ? '/pgc/web/follow/add' : '/pgc/web/follow/del'),
    {'season_id': '$seasonId'},
    what: 'pgc follow',
  );

  /// Season search: [movies] = films and series (`media_ft`), else anime
  /// (`media_bangumi`).
  Future<VodPage<PgcCard>> search(String keyword, {int page = 1, bool movies = false}) async {
    if (keyword.trim().isEmpty) return const VodPage([]);
    return await client.signed(
      Uri.https(_api, '/x/web-interface/wbi/search/type'),
      {'search_type': movies ? 'media_ft' : 'media_bangumi', 'keyword': keyword.trim(), 'page': '$page'},
      (r) => VodParse.searchSeasons(r.text, status: r.status),
      referer: 'https://search.bilibili.com/',
    );
  }
}
