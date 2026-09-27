import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _expiry = ScrubRule.expiryPrefixed;

/// NetEase CC: spec/sites/cc.md §11 "需要脱敏的字段".
///
/// Streamer public data stays real (ADR 0009 rule 4): ccid, uid, channel and
/// room ids, nickname, portrait, title, cover, stream names and the
/// `vbr`/`wsTime`/`volcTime` timing fields. The anonymous `VISITOR` and
/// `CCTOKEN` cookies arrive as Set-Cookie and are always scrubbed by the tool.
const ScrubRules ccRules = ScrubRules(
  queryParams: {
    // CDN signatures: the list `stream_list.*.CDN_FMT` strings, the redirect
    // `m3u8` secret and the `video_play_url` FLV URLs. `auth_key` and
    // `relaySecret` start with their Unix time, which the lease reads.
    'wsSecret': _secret, 'secret': _secret, 'volcSecret': _secret,
    'auth_key': _expiry, 'relaySecret': _expiry,
    // The visitor id the web player sends to `video_play_url` (`sid`).
    'sid': _secret,
  },
);
