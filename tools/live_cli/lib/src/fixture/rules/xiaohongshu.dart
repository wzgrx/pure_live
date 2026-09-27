import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _person = ScrubRule.person;

/// Xiaohongshu (link-only): spec/sites/xiaohongshu.md §11 "需要脱敏的字段".
///
/// The share page carries the host's public data (room id, nickname, avatar,
/// cover, title, host id), which ADR 0009 rule 4 keeps real. Viewer comments
/// in the page state (`liveStream.comments`) get pseudonyms when present;
/// anonymous cookies (`xsecappid`, `a1`, `webId`) arrive as Set-Cookie and
/// are always scrubbed by the tool.
const ScrubRules xiaohongshuRules = ScrubRules(jsonKeys: {'userId': _person, 'userName': _person, 'nickname': _person});
