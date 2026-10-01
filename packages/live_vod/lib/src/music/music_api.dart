import 'package:live_core/live_core.dart';
import 'package:live_vod/src/client.dart';
import 'package:live_vod/src/models.dart';
import 'package:live_vod/src/parse.dart';
import 'package:live_vod/src/streams.dart';
import 'package:live_vod/src/ugc_api.dart';

const String _api = 'api.bilibili.com';

/// A track of music mode: one part of an archive (bmsc's "a song is a
/// part").
final class MusicTrack {
  /// Creates a track.
  const new({required this.archive, required this.part});

  /// Reads the stored shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => MusicTrack(
    archive: VodArchive.fromJson(
      json['archive'] is Map<String, Object?> ? json['archive']! as Map<String, Object?> : const {},
    ),
    part: VodPart.fromJson(json['part'] is Map<String, Object?> ? json['part']! as Map<String, Object?> : const {}),
  );

  /// The archive.
  final VodArchive archive;

  /// The part.
  final VodPart part;

  /// Identity in queues and caches: `bvid_p{page}` (the cid may be unknown
  /// for list rows and is filled on first play).
  String get id => '${archive.bvid}_p${part.page}';

  /// Display title: the part title, or the archive's for single parts.
  String get title => archive.partCount > 1 && part.title.isNotEmpty ? part.title : archive.title;

  /// The stored shape.
  Map<String, Object?> toJson() => {'archive': archive.toJson(), 'part': part.toJson()};

  /// Every part of [archive] as tracks.
  static List<MusicTrack> of(VodArchive archive) => [
    for (final part in archive.playableParts) MusicTrack(archive: archive, part: part),
  ];
}

/// The Bilibili side of music mode (pure_live_TV `b9d2f739`
/// `bilibili_music_api.dart`, `bilibili_lyric_api.dart`): a track's audio
/// stream, an archive's parts, uploader playlists (seasons and series) and
/// the archive's own BGM lyric.
final class BilibiliMusicApi {
  /// Creates the API over [ugc].
  const new(this.ugc);

  /// The UGC API it builds on.
  final BilibiliUgcApi ugc;

  BilibiliVodClient get _client => ugc.client;

  /// The archive with its parts, for a track list.
  Future<List<MusicTrack>> tracks(String bvid) async => MusicTrack.of(await ugc.detail(bvid));

  /// [track] with its cid filled from the detail when the row had none.
  Future<MusicTrack> resolve(MusicTrack track) async {
    if (track.part.cid > 0) return track;
    final archive = await ugc.detail(track.archive.bvid);
    final parts = archive.playableParts;
    final part = parts.firstWhere((part) => part.page == track.part.page, orElse: () => parts.first);
    if (part.cid <= 0) throw ApiChanged(vodSite, 'view: no cid for ${track.archive.bvid}');
    return MusicTrack(archive: archive, part: part);
  }

  /// The audio of [track]: the DASH answer and the best audio rendition
  /// ([lossless] prefers Hi-Res when the account gets it). Audio renditions
  /// do not depend on the video quality, so the lowest video is asked for.
  Future<({VodStreams streams, VodRendition audio})> audio(MusicTrack track, {bool lossless = false}) async {
    final resolved = await resolve(track);
    final streams = await ugc.streams(bvid: resolved.archive.bvid, cid: resolved.part.cid, qn: 16);
    final audio = streams.bestAudio(lossless: lossless);
    if (audio == null) throw StreamUnavailable(vodSite, 'playurl: no audio for ${track.id}');
    return (streams: streams, audio: audio);
  }

  /// An uploader's seasons and series (`seasons_series_list`); guests too.
  Future<VodPage<VodUpCollection>> collections(int mid, {int page = 1, int pageSize = 20}) async {
    final r = await _client.get(
      Uri.https(_api, '/x/polymer/web-space/seasons_series_list'),
      query: {'mid': mid, 'page_num': page, 'page_size': pageSize},
      referer: 'https://space.bilibili.com/$mid/',
    );
    return VodParse.collections(r.text, mid: mid, status: r.status);
  }

  /// The archives of [collection], in its order.
  Future<VodPage<VodArchive>> collectionArchives(VodUpCollection collection, {int page = 1, int pageSize = 30}) async {
    final r = collection.isSeries
        ? await _client.get(
            Uri.https(_api, '/x/series/archives'),
            query: {
              'mid': collection.mid,
              'series_id': collection.id,
              'only_normal': 'true',
              'sort': 'desc',
              'pn': page,
              'ps': pageSize,
            },
          )
        : await _client.get(
            Uri.https(_api, '/x/polymer/web-space/seasons_archives_list'),
            query: {
              'mid': collection.mid,
              'season_id': collection.id,
              'sort_reverse': 'false',
              'page_num': page,
              'page_size': pageSize,
            },
          );
    return VodParse.collectionArchives(r.text, status: r.status);
  }

  /// The BGM of a part as `x/player/wbi/v2` names it, and its lyric: the
  /// detail's `mv_lyric` is the URL of an LRC file (the TV client read it as
  /// the lyric text, so this source never produced a lyric). Null when the
  /// part has no BGM or the BGM has no lyric.
  Future<({String title, String artist, String lrc})?> bgmLyric({
    required String bvid,
    required int cid,
    int aid = 0,
  }) async {
    final info = await ugc.playerInfo(bvid: bvid, cid: cid, aid: aid);
    if (info.bgmMusicId.isEmpty) return null;
    final r = await _client.get(
      Uri.https(_api, '/x/copyright-music-publicity/bgm/detail'),
      query: {'music_id': info.bgmMusicId, 'relation_from': 'bgm_page'},
    );
    final data = VodParse.object(VodParse.data(r.text, status: r.status, what: 'bgm detail'));
    final url = normalizeImageUrl(data?['mv_lyric']);
    if (url.isEmpty) return null;
    final lyric = await _client.file(Uri.parse(url.replaceFirst('http://', 'https://')));
    if (!lyric.isSuccess || lyric.text.trim().isEmpty) return null;
    return (
      title: jsonString(data?['music_title']) ?? info.bgmTitle,
      artist: jsonString(data?['origin_artist']) ?? '',
      lrc: lyric.text,
    );
  }
}
