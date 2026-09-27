import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

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
