import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// SOOP: spec/sites/soop.md §11 "需要脱敏的字段".
///
/// Streamer public data stays real (ADR 0009 rule 4): bj id, nick, broadcast
/// number, chat room number and server, titles, thumbnails, view counts.
/// The session cookies SOOP sets arrive as Set-Cookie and are always
/// scrubbed by the tool.
const ScrubRules soopRules = ScrubRules(
  jsonKeys: {
    // Stream key (`player_live_api` type=aid) and the colony token.
    'AID': _secret, 'AID_H': _secret, 'COLONY_CONTENT': _secret,
  },
  queryParams: {
    // Signed HLS master playlist of the player API (`TS`, `TS_SNAPSHOT`).
    'data': _secret, 'aid': _secret,
  },
);
