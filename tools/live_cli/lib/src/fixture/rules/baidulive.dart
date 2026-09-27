import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

const _viewer = r'$.data.371.online_user_list[*]';

/// Baidu Live: spec/sites/baidulive.md §11 "需要脱敏的字段".
///
/// Streamer public data (room id, uk, name, avatar, title, cover) stays real
/// (ADR 0009 rule 4). The room command lists the top viewers
/// (`online_user_list`), which get pseudonyms. The chat playlists carry BCE
/// access signatures (`authorization`), which are replaced. The feed request
/// signature is computed from a public web constant and the timestamp, so it
/// stays readable.
const ScrubRules baiduliveRules = ScrubRules(
  jsonPaths: {
    '$_viewer.uid': _person,
    '$_viewer.name': _person,
    '$_viewer.nick_name': _person,
    '$_viewer.avatar': _person,
  },
  queryParams: {'authorization': _secret},
);
