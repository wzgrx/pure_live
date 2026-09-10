import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/danmaku/empty_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/plugins/locale_helper.dart';

import 'niconico_api.dart';
import 'niconico_input_recipe.dart';
import 'niconico_quality_catalog.dart';
import 'niconico_watch.dart';

class _Choice {
  const _Choice(this.programId, this.quality);
  final String programId;
  final NiconicoQuality quality;
  Map<String, Object> toJson() => {'programId': programId, ...quality.toJson()};
}

/// Program-specific playback adapter. Directory/navigation registration is a
/// separate acceptance stage; this class never persists a watch bootstrap.
class NiconicoSite extends LiveSite
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LivePlayUrlCursorResolver {
  NiconicoSite({NiconicoApi? api, NiconicoQualityCatalog? catalog})
    : _api = api ?? NiconicoApi(),
      _catalog = catalog ?? NiconicoQualityCatalog(api: api);
  final NiconicoApi _api;
  final NiconicoQualityCatalog _catalog;
  @override
  String get id => 'niconico';
  @override
  String get name => 'niconico';
  @override
  LiveDanmaku getDanmaku() => EmptyDanmaku();

  String _identity(String roomId, String platform) {
    if (platform != id) throw const NiconicoException(NiconicoFailure.identity);
    return NiconicoWatch.validateProgramId(roomId);
  }

  Future<LiveRoom> _detail(String roomId, String platform) async {
    final programId = _identity(roomId, platform);
    final watch = await _api.room(programId);
    final notice = switch (watch.access) {
      NiconicoAccess.loginRequired => i18n('niconico_login_required'),
      NiconicoAccess.regionRestricted => i18n('niconico_region_restricted'),
      NiconicoAccess.denied => i18n('niconico_access_restricted'),
      NiconicoAccess.allowed => null,
    };
    return LiveRoom(
      platform: id,
      roomId: programId,
      title: watch.title,
      nick: watch.broadcaster,
      cover: watch.cover ?? '',
      avatar: watch.avatar ?? '',
      link: '${NiconicoApi.origin}/watch/$programId',
      liveStatus: watch.status == NiconicoStatus.onAir ? LiveStatus.live : LiveStatus.offline,
      totalViewers: watch.reportedWatchCount?.toString(),
      audienceMetricType: AudienceMetricType.totalViewers,
      notice: [
        if (watch.status == NiconicoStatus.scheduled) i18n('niconico_scheduled'),
        if (watch.status == NiconicoStatus.onAir && notice != null) notice,
        i18n('niconico_program_scope'),
      ].join(' '),
    );
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) => _detail(roomId, platform);
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      _detail(roomId, platform);
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      _detail(roomId, platform);
  @override
  Future<bool> getLiveStatus({required String platform, required String roomId}) async =>
      (await _detail(roomId, platform)).isLiveNow;

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    final programId = _identity(detail.roomId ?? '', detail.platform ?? '');
    if (detail.isExplicitlyOfflineNow) return const [];
    final choices = await _catalog.load(programId);
    return List.unmodifiable([
      for (final choice in choices)
        LivePlayQuality(id: choice.id, quality: choice.label, data: _Choice(programId, choice)),
    ]);
  }

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final programId = _identity(detail.roomId ?? '', detail.platform ?? '');
    if (detail.isExplicitlyOfflineNow) throw const NiconicoException(NiconicoFailure.notLive);
    final choice = quality.data;
    if (choice is! _Choice || choice.programId != programId || quality.selectionId != choice.quality.id) {
      throw const NiconicoException(NiconicoFailure.identity);
    }
    return LivePlayUrlResolution.owned(
      input: NiconicoInputRecipe(
        programId: programId,
        resolution: choice.quality.resolution,
        bandwidth: choice.quality.bandwidth,
      ),
      appliedQualityData: choice.quality.id,
    );
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    await resolvePlayUrlsRaw(detail: detail, quality: quality);
    return const [];
  }

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => resolvePlayUrlsRaw(detail: detail, quality: quality);
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlAtRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
    required int lineIndex,
  }) {
    if (lineIndex != 0) return Future.value(const LivePlayUrlResolution(urls: []));
    return resolvePlayUrlsRaw(detail: detail, quality: quality);
  }
}
