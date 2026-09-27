import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// YouTube: spec/sites/youtube.md §11 "需要脱敏的字段".
///
/// Channels' and broadcasts' public data (ids, titles, names, thumbnails,
/// view counts) stays real (ADR 0009 rule 4). Every response names this
/// anonymous visitor (`visitorData`, the tracking `vm`/`cpn`/`plid`
/// parameters) and the player response carries heartbeat and attestation
/// material. Manifest URLs put the requester's IP and the signature in
/// path segments (`/ip/…/`, `/sig/…/`), which query rules cannot reach; the
/// capture script replaces those afterwards and records it in meta.json.
const ScrubRules youtubeRules = ScrubRules(
  jsonKeys: {
    'visitorData': _secret,
    'heartbeatServerData': _secret,
    'serializedExperimentFlags': _secret,
    'botguardData': _secret,
    'playerAttestationRenderer': _secret,
  },
  queryParams: {
    'vm': _secret,
    'cpn': _secret,
    'plid': _secret,
    'ei': _secret,
    'of': _secret,
    'sig': _secret,
    'ip': _secret,
  },
);
