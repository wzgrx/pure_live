import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// TwitCasting: spec/sites/twitcasting.md §11 "需要脱敏的字段".
///
/// Channels, broadcasts, titles and icons are public and stay (ADR 0009
/// rule 4). Pages embed a per-visitor CSRF token (three spellings) and a
/// signed web session id; the comment socket URL carries a signed token.
/// The device id (`did`) and the HLS session cookie arrive as Set-Cookie
/// and are always scrubbed by the tool.
const ScrubRules twitcastingRules = ScrubRules(
  jsonKeys: {'csrf_token': _secret},
  queryParams: {'token': _secret, 'n': _secret},
  textPatterns: {
    'data-csrf-token="([0-9a-f]{16,})"': _secret,
    'data-token="([0-9a-f]{16,})"': _secret,
    'web-authorize-session-id&quot;:&quot;([^&]+)&quot;': _secret,
  },
);
