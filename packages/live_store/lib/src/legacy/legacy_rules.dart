import 'package:live_core/live_core.dart';
import 'package:live_store/src/settings/settings.dart';

/// Conversions 3.x data needs before v4 uses it (docs/specs/UPGRADES.md, rows
/// whose module column has M9).
abstract final class LegacyRules {
  /// Notices 3.x stored for platforms whose chat was not connected yet
  /// ("远端聊天尚待接入", "remote chat is pending"); chat has landed (M5), and
  /// [LiveRoom.mergeFrom] keeps a stored notice when a refresh has none, so
  /// they are cleared once on import.
  static bool isStaleNotice(String? notice) {
    final text = notice?.trim() ?? '';
    return text.contains('远端聊天尚待接入') || text.contains('遠端聊天尚待接入') || text.contains('remote chat is pending');
  }

  /// A theme colour from 3.x: its untouched default blue becomes the brand
  /// blue (U.6b C-3); a colour the user picked stays. Accepts the forms 3.x
  /// stored (`FF2196F3`, `#2196F3`, `0xff2196f3`).
  static String themeColor(String hex) {
    var value = hex.trim().toUpperCase();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.startsWith('0X')) value = value.substring(2);
    if (value.length == 6) value = 'FF$value';
    return value == Settings.legacyThemeColor ? Settings.brandThemeColor : hex;
  }

  /// [room] without a stale notice.
  static LiveRoom clearStaleNotice(LiveRoom room) => isStaleNotice(room.notice) ? room.copyWith(notice: '') : room;

  /// The names 3.x stored for JD, Kugou and Baidu rooms whose name or title
  /// it did not get (UPGRADES X-2, 28-2; 3.x `jd_live_api.dart:231-232`,
  /// `kugou_live_api.dart:396-397`, `baidu_live_api.dart:390`). v4's
  /// adapters leave them empty instead, and [LiveRoom.mergeFrom] keeps a
  /// stored value against an empty one, so a stored stand-in would stay.
  /// (E05.4 may move this table to live_core.)
  static const Map<String, String> placeholderNames = {
    SiteIds.jdLive: 'JD Live',
    SiteIds.kugouLive: 'Kugou Live',
    SiteIds.baiduLive: 'Baidu Live',
  };

  /// [room] without 3.x's stand-ins: a nick or title equal to its platform's
  /// [placeholderNames] becomes empty; JD's also lose the broadcast id 3.x
  /// used as the user id and the cover it used as the avatar
  /// (`jd_live_site.dart:85`, `:88`). Other platforms and fields stay; the
  /// same room comes back when there is nothing to clear.
  static LiveRoom clearPlaceholders(LiveRoom room) {
    final standIn = placeholderNames[room.platform];
    if (standIn == null) return room;
    final jd = room.platform == SiteIds.jdLive;
    final nick = room.nick.trim() == standIn;
    final title = room.title.trim() == standIn;
    final userId = jd && room.userId != null && room.userId!.isNotEmpty && room.userId == room.roomId;
    final avatar = jd && room.avatar.isNotEmpty && room.avatar == room.cover;
    if (!nick && !title && !userId && !avatar) return room;
    return room.copyWith(
      nick: nick ? '' : null,
      title: title ? '' : null,
      userId: userId ? '' : null,
      avatar: avatar ? '' : null,
    );
  }

  /// A 3.x quality id of [platform] as the platform names it now
  /// (`*Api.qualityIdFromLegacy`: CC, LiveMe, Missevan, Kilakila,
  /// Xiaohongshu, PandaTV, TikTok, Baidu, 17LIVE); other platforms kept
  /// their ids. Apply once, to 3.x data only: CC's `high` exists before and
  /// after with different meanings.
  static String qualityId(String platform, String id) => switch (platform.trim().toLowerCase()) {
    SiteIds.cc => CcApi.qualityIdFromLegacy(id),
    SiteIds.liveMe => LiveMeApi.qualityIdFromLegacy(id),
    SiteIds.missevan => MissevanApi.qualityIdFromLegacy(id),
    SiteIds.kilakila => KilakilaApi.qualityIdFromLegacy(id),
    SiteIds.xiaohongshu => XiaohongshuApi.qualityIdFromLegacy(id),
    SiteIds.pandaLive => PandaLiveApi.qualityIdFromLegacy(id),
    SiteIds.tiktok => TikTokApi.qualityIdFromLegacy(id),
    SiteIds.baiduLive => BaiduLiveApi.qualityIdFromLegacy(id),
    SiteIds.seventeenLive => SeventeenLiveApi.qualityIdFromLegacy(id),
    _ => id,
  };

  /// Whether [room]'s id is one 3.x stored per broadcast and v4 follows by
  /// streamer instead: a Douyin room_id (UPGRADES M9 note, `DouyinApi.isRoomId`),
  /// a niconico programme `lv…` (17-1) or a YouTube video id (23-1).
  /// Converting it needs the network; see `IdentityMigration`.
  static bool needsIdentityMigration(LiveRoom room) => switch (room.platform) {
    SiteIds.douyin => DouyinApi.isRoomId(room.roomId),
    SiteIds.niconico => NiconicoApi.isProgramId(room.roomId),
    SiteIds.youtube => YouTubeApi.isVideoId(room.roomId) && !YouTubeApi.isChannelId(room.roomId),
    _ => false,
  };

  /// 3.x's platform-list versions (favorite_room_controller.dart:58-96):
  /// version `index + 3` added `catalogAdditions[index]`; retired platforms
  /// keep their slot and are never added again.
  static const List<String> catalogAdditions = [
    SiteIds.acfun,
    SiteIds.picarto,
    SiteIds.twitcasting,
    SiteIds.missevan,
    SiteIds.inke,
    SiteIds.kilakila,
    'huajiao',
    'openrec',
    'ttinglive',
    SiteIds.xiaohongshu,
    SiteIds.niconico,
    SiteIds.weibo,
    SiteIds.showroom,
    SiteIds.chzzk,
    'kick',
    SiteIds.seventeenLive,
    SiteIds.liveMe,
    SiteIds.tiktok,
    SiteIds.youtube,
    SiteIds.bigo,
    SiteIds.pandaLive,
    'popkontv',
    'shopeelive',
    'vkvideolive',
    'nimotv',
    'dailymotion',
    'rumble',
    'goodgame',
    SiteIds.fc2Live,
    SiteIds.steamBroadcast,
    SiteIds.jdLive,
    'taobaolive',
    SiteIds.kugouLive,
    SiteIds.baiduLive,
    SiteIds.sixRoom,
    SiteIds.lookLive,
  ];

  /// 3.x's current platform-list version.
  static const int currentCatalogVersion = 38;

  /// The home platforms after 3.x's start-up repairs: ids trimmed and
  /// lower-cased, unsupported and repeated ones dropped, then the platforms
  /// added after [version] appended (3.x `_normalizeSiteCatalogIds` and
  /// `_migrateSiteCatalog`).
  static List<String> homePlatforms(Iterable<String> stored, int version) {
    final seen = <String>{};
    final list = [
      for (final raw in stored)
        if (SiteIds.isSupported(raw) && seen.add(raw.trim().toLowerCase())) raw.trim().toLowerCase(),
    ];
    if (version >= currentCatalogVersion) return list;
    if (version < 2) {
      for (final site in SiteIds.supported) {
        if (seen.add(site)) list.add(site);
      }
    }
    for (var index = 0; index < catalogAdditions.length; index++) {
      final site = catalogAdditions[index];
      if (SiteIds.isRetired(site) || !SiteIds.isSupported(site)) continue;
      if (version < index + 3 && seen.add(site)) list.add(site);
    }
    return list;
  }

  /// The preferred platform: lower-cased, bilibili when unsupported, the
  /// first home platform when hidden (3.x `_normalizePreferredPlatform`).
  static String preferredPlatform(String stored, List<String> home) {
    final id = stored.trim().toLowerCase();
    final supported = SiteIds.isSupported(id) ? id : SiteIds.bilibili;
    return home.isNotEmpty && !home.contains(supported) ? home.first : supported;
  }

  /// 3.x's real-online-count platforms after its numbered additions (twitch,
  /// soop, acfun, picarto, twitcasting for versions 1..5;
  /// app_settings_controller.dart:75-100), trimmed and de-duplicated.
  static List<String> realOnlinePlatforms(Iterable<String> stored, int version) {
    const additions = [SiteIds.twitch, SiteIds.soop, SiteIds.acfun, SiteIds.picarto, SiteIds.twitcasting];
    final list = <String>[];
    for (final raw in [...stored, for (var i = version; i < additions.length; i++) additions[i]]) {
      final id = raw.trim().toLowerCase();
      if (id.isNotEmpty && !list.contains(id)) list.add(id);
    }
    return list;
  }

  /// Bottom-menu ids: known ones, de-duplicated; never empty (3.x
  /// `normalizeMenuIds`).
  static List<String> menuIds(Iterable<String> stored) {
    const known = {'favorites', 'popular', 'areas', 'record'};
    final list = <String>[];
    for (final raw in stored) {
      final id = raw.trim().toLowerCase();
      if (known.contains(id) && !list.contains(id)) list.add(id);
    }
    return list.isEmpty ? const ['favorites'] : list;
  }
}
