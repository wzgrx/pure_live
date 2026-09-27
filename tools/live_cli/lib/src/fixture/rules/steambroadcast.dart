import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// Steam broadcasts: spec/sites/steambroadcast.md §11 "需要脱敏的字段".
///
/// Broadcaster public data (steam id, persona name, avatar, broadcast id,
/// titles, viewer counts) stays real (ADR 0009 rule 4). `getbroadcastmpd`
/// issues a per-viewer `viewertoken`, which is replaced; the chat frames are
/// scrubbed by the danmaku recorder.
const ScrubRules steambroadcastRules = ScrubRules(
  jsonKeys: {'viewertoken': _secret},
  queryParams: {'viewertoken': _secret, 'sessionid': _secret},
);
