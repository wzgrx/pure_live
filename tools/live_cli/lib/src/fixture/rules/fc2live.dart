import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// FC2 Live: spec/sites/fc2live.md §11 "需要脱敏的字段".
///
/// Streamers' public data (channel ids, FC2 ids, names, titles, images,
/// counts) stays real (ADR 0009 rule 4). The control grant carries this
/// client's anonymous session (`control_token`, `orz`, `orz_raw`); the
/// media playlists are authorised by the `c` and `d` parameters, and
/// segment URLs by `hash`.
const ScrubRules fc2liveRules = ScrubRules(
  jsonKeys: {'control_token': _secret, 'orz': _secret, 'orz_raw': _secret},
  queryParams: {'c': _secret, 'd': _secret, 'hash': _secret, 'control_token': _secret},
);
