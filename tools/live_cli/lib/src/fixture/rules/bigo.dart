import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// Bigo Live: spec/sites/bigo.md §11 "需要脱敏的字段".
///
/// Streamers' public data (bigo id, owner uid, nickname, topic, counts)
/// stays real (ADR 0009 rule 4). The web token (`token`) and the encrypted
/// token request (`data`) are this client's session material; image URLs
/// carry an `auth-token` signature; the studio answer may echo `client_ip`.
const ScrubRules bigoRules = ScrubRules(
  jsonKeys: {'token': _secret, 'client_ip': _secret},
  queryParams: {'token': _secret, 'data': _secret, 'auth-token': _secret},
);
