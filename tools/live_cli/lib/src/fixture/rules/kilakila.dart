import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// KilaKila: spec/sites/kilakila.md §11 "需要脱敏的字段".
///
/// Anchor and room data (uids, broadcast ids, names, avatars, titles,
/// introductions, display numbers) are public and stay (ADR 0009 rule 4).
/// Every room object carries the anchor's RTMP push address with its key
/// (`pushFlow`): replaced whole. Pull URLs keep the expiry that leads their
/// Aliyun `auth_key` (`<expiry>-0-0-<md5>`); only the hash is replaced.
/// Session cookies arrive as Set-Cookie and are always scrubbed by the tool.
const ScrubRules kilakilaRules = ScrubRules(
  jsonKeys: {'pushFlow': _secret},
  textPatterns: {r'auth_key=\d+-\d+-\d+-([0-9a-f]{32})': _secret},
);
