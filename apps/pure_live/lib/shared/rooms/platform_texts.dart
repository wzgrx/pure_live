import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/i18n/i18n.dart';

// Words the adapters write for users in Chinese (notices, explanations, the
// areas and qualities they name themselves, chat notices), shown in the
// interface language (Z05.2). 3.x's adapters called `i18n`; `live_core` and
// `live_danmaku` have no translations, so they keep writing Chinese (what
// follows, backups and recordings store) and the app swaps each known text
// for its key's text when it shows it. The Chinese text of every key equals
// the adapter's constant (test/shared/platform_texts_test.dart), so the
// Chinese interface is unchanged.

/// Notice and chat lines the adapters write, by their Chinese text. A text
/// with `{value}` stands for the line built with a value there.
final Map<String, String> platformLineKeys = {
  // Room notices: restrictions and what the figures mean.
  BaiduLiveApi.chatNotice: 'baidulive_chat_notice',
  BaiduLiveApi.restrictedNotice: 'baidulive_restricted_notice',
  BigoApi.chatNotice: 'bigo_chat_notice',
  BigoApi.loginNotice: 'bigo_login_required',
  BigoApi.restrictedNotice: 'bigo_access_restricted',
  ChzzkApi.adultNotice: 'chzzk_adult_notice',
  ChzzkApi.regionNotice: 'chzzk_region_notice',
  ChzzkApi.timeMachineNotice: 'chzzk_time_machine_notice',
  Fc2LiveApi.noticeText['fc2live_access_restricted']!: 'fc2live_access_restricted',
  Fc2LiveApi.noticeText['fc2live_adult_notice']!: 'fc2live_adult_notice',
  JdLiveApi.chatNotice: 'jdlive_chat_notice',
  JdLiveApi.restrictedNotice: 'jdlive_restricted_notice',
  KickApi.matureNotice: 'kick_mature_notice',
  KugouLiveApi.chatNotice: 'kugoulive_chat_notice',
  KugouLiveApi.restrictedNotice: 'kugoulive_restricted_notice',
  LiveMeApi.chatNotice: 'liveme_chat_notice',
  LookLiveApi.appOnlyNotice: 'looklive_app_only_notice',
  LookLiveApi.bannedNotice: 'looklive_banned_notice',
  LookLiveApi.chatNotice: 'looklive_chat_notice',
  LookLiveApi.paidNotice: 'looklive_paid_notice',
  NiconicoApi.noticeText['niconico_access_restricted']!: 'niconico_access_restricted',
  NiconicoApi.noticeText['niconico_login_required']!: 'niconico_login_required',
  NiconicoApi.noticeText['niconico_program_scope']!: 'niconico_program_scope',
  NiconicoApi.noticeText['niconico_region_restricted']!: 'niconico_region_restricted',
  NiconicoApi.noticeText['niconico_scheduled']!: 'niconico_scheduled',
  PandaLiveApi.adultNotice: 'pandalive_adult_notice',
  PandaLiveApi.chatNotice: 'pandalive_chat_notice',
  PandaLiveApi.fansNotice: 'pandalive_fans_notice',
  PandaLiveApi.passwordNotice: 'pandalive_password_notice',
  PandaLiveApi.restrictedNotice: 'pandalive_restricted_notice',
  SeventeenLiveApi.ageNotice: 'seventeen_age_notice',
  SixRoomApi.chatNotice: 'sixroom_chat_notice',
  SixRoomApi.restrictedNotice: 'sixroom_restricted_notice',
  SteamBroadcastApi.chatNotice: 'steambroadcast_chat_notice',
  SteamBroadcastApi.restrictedNotice: 'steambroadcast_restricted_notice',
  TikTokApi.chatNotice: 'tiktok_chat_notice',
  WeiboApi.disabledNotice: 'weibo_disabled_notice',
  WeiboApi.restrictedNotice: 'weibo_restricted',
  WeiboApi.roomScopeNotice: 'weibo_room_scope',
  XiaohongshuApi.displayViewersNotice('{value}'): 'xiaohongshu_display_viewers',
  XiaohongshuApi.restrictedNotice: 'xiaohongshu_restricted',
  XiaohongshuApi.roomScopeNotice: 'xiaohongshu_room_scope',
  XiaohongshuApi.unknownAccessNotice: 'xiaohongshu_unknown_access',
  YouTubeApi.chatNotice: 'youtube_chat_notice',
  // Chat notices the danmaku connections write themselves.
  BilibiliDanmakuProtocol.cutOffNotice: 'bilibili_cut_off_notice',
  BilibiliDanmakuProtocol.warningNotice: 'bilibili_warning_notice',
  KickDanmakuProtocol.streamEndedNotice: 'kick_stream_ended_notice',
  MissevanDanmakuProtocol.globalPkLines['finish']!: 'missevan_global_pk_finish',
  MissevanDanmakuProtocol.globalPkLines['match_fail']!: 'missevan_global_pk_match_fail',
  MissevanDanmakuProtocol.globalPkLines['match_ready']!: 'missevan_global_pk_match_ready',
  MissevanDanmakuProtocol.globalPkLines['match_skip']!: 'missevan_global_pk_match_skip',
  MissevanDanmakuProtocol.globalPkLines['match_start']!: 'missevan_global_pk_match_start',
  MissevanDanmakuProtocol.globalPkLines['match_success']!: 'missevan_global_pk_match_success',
  MissevanDanmakuProtocol.globalPkResults[0]!: 'missevan_global_pk_lost',
  MissevanDanmakuProtocol.globalPkResults[1]!: 'missevan_global_pk_won',
  MissevanDanmakuProtocol.globalPkResults[2]!: 'missevan_global_pk_drawn',
  MissevanDanmakuProtocol.pkLines['invite_refuse']!: 'missevan_pk_invite_declined',
  MissevanDanmakuProtocol.pkLines['match_start']!: 'missevan_pk_match_start',
  MissevanDanmakuProtocol.pkLines['match_success']!: 'missevan_pk_match_success',
  MissevanDanmakuProtocol.pkResults[0]!: 'missevan_pk_lost',
  MissevanDanmakuProtocol.pkResults[1]!: 'missevan_pk_won',
  MissevanDanmakuProtocol.pkResults[2]!: 'missevan_pk_drawn',
  NiconicoDanmakuProtocol.commentUnlockedNotice: 'niconico_comment_unlocked_notice',
  SeventeenLiveDanmakuProtocol.mutedNotice: 'seventeen_muted_notice',
  SeventeenLiveDanmakuProtocol.unmutedNotice: 'seventeen_unmuted_notice',
  TwitchDanmakuProtocol.cookieExpiredNotice.message: 'twitch_cookie_expired_notice',
};

/// Area and category names the adapters give themselves (translated from
/// the platform's codes or language), by platform. Names the platforms give
/// in Chinese (the domestic platforms' areas) are theirs and stay.
final Map<String, Map<String, String>> platformAreaKeys = {
  SiteIds.bigo: {BigoApi.areaName: 'bigo_category_public'},
  SiteIds.cc: {CcApi.officialLabel: 'cc_official_entries'},
  SiteIds.chzzk: {
    ChzzkApi.directoryAreaName: 'chzzk_public_directory',
    ChzzkApi.categoryTypeNames['ENTERTAINMENT']!: 'chzzk_category_entertainment',
    ChzzkApi.categoryTypeNames['ETC']!: 'chzzk_category_etc',
    ChzzkApi.categoryTypeNames['GAME']!: 'chzzk_category_game',
    ChzzkApi.categoryTypeNames['SPORTS']!: 'chzzk_category_sports',
  },
  SiteIds.fc2Live: {
    Fc2LiveApi.areaNames['all']!: 'fc2live_category_all',
    Fc2LiveApi.areaNames['1']!: 'fc2live_category_chat',
    Fc2LiveApi.areaNames['2']!: 'fc2live_category_game',
    Fc2LiveApi.areaNames['4']!: 'fc2live_category_video',
    Fc2LiveApi.areaNames['5']!: 'fc2live_category_other',
    Fc2LiveApi.areaNames['9']!: 'fc2live_category_audio',
  },
  SiteIds.jdLive: {JdLiveApi.areaName: 'jdlive_category_featured'},
  SiteIds.kick: {
    KickApi.categoryNames['alternative']!: 'kick_category_alternative',
    KickApi.categoryNames['creative']!: 'kick_category_creative',
    KickApi.categoryNames['gambling']!: 'kick_category_gambling',
    KickApi.categoryNames['games']!: 'kick_category_games',
    KickApi.categoryNames['irl']!: 'kick_category_irl',
    KickApi.categoryNames['music']!: 'kick_category_music',
  },
  SiteIds.lookLive: {
    LookLiveApi.audioAreaName: 'looklive_category_audio',
    LookLiveApi.videoAreaName: 'looklive_category_video',
  },
  SiteIds.niconico: {
    NiconicoApi.tabNames['common']!: 'niconico_category_common',
    NiconicoApi.tabNames['face']!: 'niconico_category_face',
    NiconicoApi.tabNames['live']!: 'niconico_category_live',
    NiconicoApi.tabNames['req']!: 'niconico_category_req',
    NiconicoApi.tabNames['totu']!: 'niconico_category_totu',
    NiconicoApi.tabNames['try']!: 'niconico_category_try',
  },
  SiteIds.pandaLive: {
    PandaLiveApi.directoryAreaName: 'pandalive_public_directory',
    PandaLiveApi.newBroadcasterAreaName: 'pandalive_category_newbj',
    PandaLiveApi.areaNames['etc']!: 'pandalive_category_etc',
    PandaLiveApi.areaNames['game']!: 'pandalive_category_game',
    PandaLiveApi.areaNames['ind']!: 'pandalive_category_ind',
    PandaLiveApi.areaNames['music']!: 'pandalive_category_music',
    PandaLiveApi.areaNames['sports']!: 'pandalive_category_sports',
    PandaLiveApi.areaNames['talk']!: 'pandalive_category_talk',
  },
  SiteIds.picarto: {PicartoApi.publicDirectory.areaName: 'picarto_public_directory'},
  SiteIds.seventeenLive: {
    SeventeenLiveApi.audioRoom: 'seventeen_audio_room',
    SeventeenLiveApi.categoryName: 'seventeen_category_region',
    SeventeenLiveApi.regions['HK']!: 'seventeen_region_hk',
    SeventeenLiveApi.regions['JP']!: 'seventeen_region_jp',
    SeventeenLiveApi.regions['TW']!: 'seventeen_region_tw',
  },
  SiteIds.soop: {SoopApi.category.name: 'soop_category_hot'},
  SiteIds.steamBroadcast: {SteamBroadcastApi.areaName: 'steambroadcast_category_trending'},
  SiteIds.weibo: {WeiboApi.areaName: 'weibo_public_directory'},
};

/// Quality names the adapters give (`LiveQualityLabel`'s shared names and
/// the adapters' own), by their Chinese text. A name such as `原画 · FLV`
/// is shown part by part.
final Map<String, String> qualityNameKeys = {
  '1080P 高清': 'quality_name_1080p',
  '2K 超清': 'quality_name_2k',
  '360P 极速': 'quality_name_360p',
  '480P 流畅': 'quality_name_480p',
  '720P 清晰': 'quality_name_720p',
  BaiduLiveApi.replayQualityName: 'quality_name_replay',
  BigoApi.quality.quality: 'bigo_quality_live',
  Fc2LiveApi.autoQuality.quality: 'fc2live_quality_auto',
  Fc2LiveApi.tierQualities[0].quality: 'fc2live_quality_3m',
  Fc2LiveApi.tierQualities[1].quality: 'fc2live_quality_2m',
  JdLiveApi.flvQuality.quality: 'quality_name_flv_source',
  JdLiveApi.hlsQuality.quality: 'jdlive_quality_hls',
  LookLiveApi.hlsQuality.quality: 'quality_name_hls_source',
  SeventeenLiveApi.qualityNames['enhanced']!: 'seventeen_quality_enhanced',
  TikTokApi.qualityNames['hd_60']!: 'tiktok_quality_hd60',
  TikTokApi.qualityNames['origin']!: 'tiktok_quality_origin',
  TikTokApi.qualityNames['uhd_60']!: 'tiktok_quality_uhd60',
  WeiboApi.original.quality: 'weibo_original_stream',
  YouTubeApi.dashAutoLabel: 'youtube_quality_dash_auto',
  YouTubeApi.hlsAutoLabel: 'youtube_quality_hls_auto',
  '中画质': 'showroom_quality_medium',
  '低画质': 'showroom_quality_low',
  '低清': 'quality_name_low',
  '原画': 'quality_name_original',
  '杜比': 'quality_name_dolby',
  '标准': 'quality_name_standard',
  '标清': 'quality_name_sd',
  '流畅': 'quality_name_smooth',
  '蓝光': 'quality_name_bluray',
  '自动': 'quality_name_auto',
  '超清': 'quality_name_super_hd',
  '高清': 'quality_name_hd',
  '高码率': 'quality_name_high_bitrate',
  '默认': 'quality_name_default',
};

/// The lines with a value: a pattern of the line and the key.
final List<(RegExp, String)> _templates = [
  for (final MapEntry(key: text, value: key) in platformLineKeys.entries)
    if (text.contains('{value}'))
      (RegExp('^${RegExp.escape(text).replaceAll(RegExp.escape('{value}'), '(.+)')}\$'), key),
];

/// [text] (a room's notice, a chat notice) in the interface language: each
/// line an adapter wrote is shown in its translation, the platform's own
/// lines as they are.
String platformNotice(String text) => text.split('\n').map(_line).join('\n');

String _line(String line) {
  if (platformLineKeys[line] case final key?) return i18n(key);
  for (final (pattern, key) in _templates) {
    if (pattern.firstMatch(line) case final match?) return i18n(key, args: {'value': match.group(1)!});
  }
  return line;
}

/// The area or category [name] of [platform] in the interface language,
/// when the adapter named it; else as it is.
String platformAreaName(String platform, String name) {
  final key = platformAreaKeys[platform.trim().toLowerCase()]?[name.trim()];
  return key == null ? name : i18n(key);
}

/// The quality [name] in the interface language: a shared name or one an
/// adapter gave, part by part (`原画 · FLV`); others as they are.
String platformQualityName(String name) {
  if (qualityNameKeys[name] case final key?) return i18n(key);
  if (!name.contains(' · ')) return name;
  return name
      .split(' · ')
      .map((part) => qualityNameKeys[part] == null ? part : i18n(qualityNameKeys[part]!))
      .join(' · ');
}
