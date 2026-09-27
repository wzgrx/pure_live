import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// AcFun: spec/sites/acfun.md §11 "需要脱敏的字段".
///
/// Streamer public data stays real (ADR 0009 rule 4): author id, name,
/// avatar, signature, live id, stream name, titles, covers and counts. The
/// anonymous `_did` and session cookies arrive as request Cookie or
/// Set-Cookie and are always scrubbed by the tool.
const ScrubRules acfunRules = ScrubRules(
  jsonKeys: {
    // Visitor session (`visitor/login`): token, security key, visitor id.
    'acfun.api.visitor_st': _secret, 'acSecurity': _secret, 'userId': _person,
    // Chat admission of `startPlay` (tickets and the room attachment).
    'availableTickets': _secret, 'enterRoomAttach': _secret,
    // Internal server names echoed by every API answer.
    'host-name': _secret,
  },
  jsonPaths: {
    // `notices[].userId` of startPlay is the official patrol account.
    r'$.data.notices[*].userId': ScrubRule.keep,
    // Internal server name of a failed startPlay.
    r'$.host': _secret,
  },
  queryParams: {
    // startPlay query: the visitor session.
    'userId': _person, 'did': _secret, 'acfun.api.visitor_st': _secret,
    // FLV signature; its leading field is the expiry the lease reads.
    'auth_key': ScrubRule.expiryPrefixed,
  },
);
