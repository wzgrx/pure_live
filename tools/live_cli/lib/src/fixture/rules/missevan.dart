import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// Missevan: spec/sites/missevan.md §11 "需要脱敏的字段".
///
/// Rooms and creators (ids, names, avatars, covers, announcements) are
/// public and stay (ADR 0009 rule 4). The pull URLs carry the caller's IP
/// as an integer (`oi`) and Bilibili CDN signatures; `expires` stays for the
/// lease. The guest session cookie arrives as Set-Cookie and is always
/// scrubbed by the tool.
const ScrubRules missevanRules = ScrubRules(
  queryParams: {'oi': _secret, 'sign': _secret, 'sk': _secret, 'trid': _secret},
  jsonKeys: {
    // Search telemetry echoes a request id.
    'ops_request_misc': _secret,
  },
);
