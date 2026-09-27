import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// YY: spec/sites/yy.md §11 "需要脱敏的字段".
///
/// Streamer public data stays real (ADR 0009 rule 4): sid/ssid, uid, yy
/// number, name, avatar, cover, stream keys and names. The expiry `t` of a
/// FLV URL stays real because the lease reads it (spec §6.3).
const ScrubRules yyRules = ScrubRules(
  queryParams: {
    // stream-manager FLV signatures.
    'rts_tk': _secret, 'secret': _secret,
    // Mobile HLS: per-request token and viewer uuid.
    'tk': _secret, 'uuid': _secret,
  },
);
