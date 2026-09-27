import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// LiveMe: spec/sites/liveme.md §11 "需要脱敏的字段".
///
/// Streamer public data (short id, user id, names, avatars, covers, counts)
/// stays real (ADR 0009 rule 4). The request signature (`lm-s-sign`, `lm_s_*`,
/// `vali`) is computed from public web constants and a timestamp, so it is
/// no credential and stays readable for review. The Wangsu CDN signatures in
/// media URLs are replaced; `wsABStime` (the expiry) stays real for lease
/// tests.
const ScrubRules livemeRules = ScrubRules(
  queryParams: {'wsSecret': _secret, 'wsIPSercert': _secret, 'wsSession': _secret},
);
