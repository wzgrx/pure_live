import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

const _rankItem = r'$.data.room_rank_info.user_rank_entry.user_contribution_rank_entry.item[*]';
const _superChat = r'$.data.super_chat_info.message_list[*]';

/// Bilibili: spec/sites/bilibili.md §11 "需要脱敏的字段".
///
/// Streamer public data (room id, anchor uid, name, face, title, cover) stays
/// real (ADR 0009 rule 4); the WBI image keys in `nav` are public and stay real
/// too (§11 #11). Cookie and Set-Cookie values (buvid3, buvid4, b_nut, SESSDATA,
/// bili_jct, DedeUserID, sid) are always scrubbed by the tool.
const ScrubRules bilibiliRules = ScrubRules(
  jsonKeys: {
    // Anonymous device ids (§11 #10 finger/spi) and their echoes.
    'b_3': _secret, 'b_4': _secret, 'buvid': _secret, 'buvid3': _secret, 'buvid4': _secret,
    // `w_webid` source in the live.bilibili.com page state (§11 #12).
    'access_id': _secret,
    // Danmaku credential (§11 #9) and login material (§11 #15).
    'token': _secret, 'qrcode_key': _secret, 'refresh_token': _secret, 'csrf': _secret, 'bili_jct': _secret,
    'SESSDATA': _secret, 'DedeUserID__ckMd5': _secret,
    // Logged-in identity (§11 #16).
    'DedeUserID': _person, 'mid': _person,
  },
  // Viewers inside getInfoByRoom (§11 #6, same identity fields as §11 #13/#14):
  // the top guard, the contribution ranking and the super chat snapshot. Their
  // keys (uid, name, face) are shared with the anchor's public fields
  // (room_info.uid, anchor_info.base_info), so they are listed by path.
  jsonPaths: {
    r'$.data.guard_leader.uid': _person,
    r'$.data.guard_leader.name': _person,
    r'$.data.guard_leader.face': _person,
    r'$.data.voice_join_info.status.uid': _person,
    r'$.data.voice_join_info.status.user_name': _person,
    '$_rankItem.uid': _person,
    '$_rankItem.name': _person,
    '$_rankItem.face': _person,
    '$_rankItem.uinfo.uid': _person,
    '$_rankItem.uinfo.base.name': _person,
    '$_rankItem.uinfo.base.face': _person,
    '$_rankItem.uinfo.base.*.name': _person,
    '$_rankItem.uinfo.base.*.face': _person,
    '$_rankItem.uinfo.base.official_info.title': _person,
    '$_rankItem.uinfo.base.official_info.desc': _person,
    '$_superChat.uid': _person,
    '$_superChat.user_info.uname': _person,
    '$_superChat.user_info.face': _person,
    '$_superChat.uinfo.uid': _person,
    '$_superChat.uinfo.base.name': _person,
    '$_superChat.uinfo.base.face': _person,
    '$_superChat.uinfo.base.*.name': _person,
    '$_superChat.uinfo.base.*.face': _person,
    '$_superChat.uinfo.base.official_info.title': _person,
    '$_superChat.uinfo.base.official_info.desc': _person,
  },
  queryParams: {
    // WBI signing material on the request side (§11 preamble).
    'w_rid': _secret, 'wts': _secret, 'w_webid': _secret,
    // Media URL signatures and client data in url_info[].extra (§11 #7):
    // signatures (sign, upsig), stream session keys (sk, flvsk), trace id
    // (trid), client IP as a decimal (oi), client location derived from it
    // (pv province, rg region, isp, zoneid_l zone id, ld) and the per-client
    // `site` hash. `expires`, `deadline` and `stream_ttl` stay real for lease
    // timing; CDN node names (cdn, sid, host) stay real per ADR 0009.
    'sign': _secret, 'upsig': _secret, 'sk': _secret, 'flvsk': _secret, 'trid': _secret,
    'oi': _secret, 'pv': _secret, 'rg': _secret, 'isp': _secret, 'zoneid_l': _secret, 'ld': _secret,
    'site': _secret, 'mid': _person,
    // Login material in QR poll URLs (§11 #15).
    'SESSDATA': _secret, 'bili_jct': _secret, 'DedeUserID': _person, 'DedeUserID__ckMd5': _secret,
    'csrf': _secret, 'refresh_token': _secret, 'qrcode_key': _secret, 'access_key': _secret,
  },
);
