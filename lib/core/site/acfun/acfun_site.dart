import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/danmaku/empty_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_play_quality.dart';

import 'acfun_api.dart';

/// Protocol-stage adapter. Navigation/search and remote chat capability must
/// be integrated before Sites advertises AcFun as a supported platform.
class AcfunSite extends LiveSite
    implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver, LivePlayRecoveryResolver {
  AcfunSite({AcfunApi? api}) : _api = api ?? _sharedApi;
  static final _sharedApi = AcfunApi();
  final AcfunApi _api;

  @override
  String get id => 'acfun';
  @override
  String get name => 'AcFun 直播';
  @override
  LiveDanmaku getDanmaku() => EmptyDanmaku();

  static LiveRoom parseRoom(Map<String, dynamic> data, String roomId) {
    final live = AcfunApi.validateRoomInfo(data, roomId);
    final user = AcfunApi.object(data['user']);
    final covers = data['coverUrls'];
    final count = AcfunApi.integer(data['onlineCount']);
    return LiveRoom(
      platform: 'acfun',
      roomId: roomId,
      userId: roomId,
      link: '${AcfunApi.origin}/live/$roomId',
      nick: AcfunApi.text(user['name']),
      avatar: AcfunApi.text(user['headUrl']),
      title: AcfunApi.text(data['title']),
      cover: covers is List && covers.isNotEmpty ? AcfunApi.text(covers.first) : '',
      area: data['type'] is Map ? AcfunApi.text((data['type'] as Map)['name']) : '',
      onlineViewers: count != null && count >= 0 ? '$count' : '',
      watching: count != null && count >= 0 ? '$count' : '',
      audienceMetricType: AudienceMetricType.onlineViewers,
      followers: AcfunApi.text(user['fanCountValue']),
      status: live,
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
    );
  }

  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) async {
    final id = AcfunApi.normalizeAuthorId(roomId);
    return parseRoom(await _api.roomInfo(id), id);
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId, platform: platform);
    if (room.liveStatus == LiveStatus.live) room.data = await _api.playback(room.roomId!);
    return room;
  }

  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      getRoomDetail(roomId: roomId, platform: platform);

  @override
  Future<bool> getLiveStatus({required String platform, required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId, platform: platform)).liveStatus == LiveStatus.live;

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.liveStatus != LiveStatus.live) return [];
    final data = detail.data;
    if (data is! AcfunPlayback) throw const AcfunApiException(AcfunFailureKind.schema);
    return [
      for (final quality in data.qualities)
        LivePlayQuality(id: quality.id, quality: quality.label, sort: quality.rank, data: quality.urls),
    ];
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = detail.data;
    if (data is! AcfunPlayback) throw const AcfunApiException(AcfunFailureKind.schema);
    for (final current in data.qualities) {
      if (current.id == quality.selectionId) return current.urls;
    }
    throw const AcfunApiException(AcfunFailureKind.qualityUnavailable);
  }

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final fresh = await getRoomDetail(roomId: detail.roomId!, platform: id);
    final urls = await getPlayUrls(detail: fresh, quality: quality);
    return LivePlayUrlResolution(urls: urls, appliedQualityData: quality.selectionId);
  }
}
