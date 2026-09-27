import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// 6.cn (六间房): spec/sites/sixroom.md §11 "需要脱敏的字段".
///
/// Streamer public data (room id, user id, alias, avatar, poster, mood,
/// stream name, encoder report) stays real (ADR 0009 rule 4); the linked-mic
/// guests of `videoConnectList` are other streamers and public too. The
/// streaming server's internal `ip` and upload host are replaced, as are
/// ranking lists of viewers when a page carries them.
const ScrubRules sixroomRules = ScrubRules(
  jsonKeys: {
    'ip': _secret, 'uploadip2': _secret,
    // Gift senders and viewers in rankings.
    'fansList': _person, 'rankList': _person,
  },
);
