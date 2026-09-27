import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// niconico live: spec/sites/niconico.md §11 "需要脱敏的字段".
///
/// Broadcasters' public data (program ids, user and channel ids, names,
/// icons, titles, counts) stays real (ADR 0009 rule 4). The watch page
/// carries this client's anonymous audience token (inside the seat socket
/// URL and as `audienceToken`), a CSRF token and `nicosid`; the program
/// lists name the top advertiser (`nicoad`), a viewer.
const ScrubRules niconicoRules = ScrubRules(
  jsonKeys: {'audienceToken': _secret, 'csrfToken': _secret, 'nicosid': _secret},
  jsonPaths: {r'$.data[*].nicoad.userName': _person, r'$.data[*].nicoad.userIcon': _person},
  queryParams: {'audience_token': _secret},
);
