import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';

/// The figure a card shows (F-DSC-05): the platform's heat first (3.x's
/// default), or concurrent viewers first when the user prefers them; the
/// other figures fill in when the first is missing.
int? shownAudience(Audience audience, {required bool preferOnline}) => preferOnline
    ? audience.online ?? audience.popularity ?? audience.cumulative
    : audience.popularity ?? audience.online ?? audience.cumulative;

/// 真实在线人数优先 (F-DSC-05; off: platform heat first).
final preferRealOnlineSetting = NotifierProvider<SettingNotifier<bool>, bool>(
  () => SettingNotifier(Settings.preferRealOnlineCounts),
);

/// What each platform's figures mean (F-DSC-05), from 3.x's measured notes.
const audienceNotes = {
  'bilibili': '列表和弹幕心跳给的是人气值，本场累计看过另算，都不是同时在线人数',
  'douyu': '公开列表的数字按热度处理，不是真实人数',
  'huya': '列表、详情和直播间里的人数实测都是热度，没有单独的在线人数',
  'douyin': '在线人数取自房间数据；累计观看另算',
  'kuaishou': '当前观看人数',
  'cc': '热度和在线人数分开：webcc 热度与 vision 在线人数',
  'yy': '公开的人数按平台热度显示，没有单独的在线人数',
  'soop': 'PC 和移动端在线总人数',
  'acfun': '在线人数；点赞和粉丝数另算',
  'twitch': '当前同时观看人数',
  'iptv': '网络电视没有人数',
};
