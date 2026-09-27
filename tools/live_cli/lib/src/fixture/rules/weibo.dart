import 'package:live_cli/src/fixture/scrub.dart';

/// Weibo Live: spec/sites/weibo.md §11 "需要脱敏的字段".
///
/// The recommendation list and the room endpoint only carry the streamer's
/// public data (uid, screen name, avatar, cover, title), which ADR 0009 rule 4
/// keeps real. Anonymous visitor cookies arrive as Set-Cookie and are always
/// scrubbed by the tool; nothing else identifies the caller.
const ScrubRules weiboRules = ScrubRules();
