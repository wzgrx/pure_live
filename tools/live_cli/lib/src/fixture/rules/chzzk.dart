import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// CHZZK: spec/sites/chzzk.md §11 "需要脱敏的字段".
///
/// Channel and live data (ids, names, images, titles, `videoId`) are public
/// and stay (ADR 0009 rule 4). The Akamai tokens keep their `st`/`exp`
/// fields (lease timing); only the `hmac` is replaced, in the master URL's
/// `hdnts` query and in the variant paths' `hdntl` segment.
const ScrubRules chzzkRules = ScrubRules(
  jsonKeys: {
    // Chat access token response (S08).
    'accessToken': _secret, 'extraToken': _secret,
  },
  queryParams: {
    // Per-viewer playback parameter on every media URL.
    'vp': _secret,
  },
  textPatterns: {'hmac=([0-9a-f]{16,})': _secret},
);
