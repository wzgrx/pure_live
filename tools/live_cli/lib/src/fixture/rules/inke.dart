import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// Inke: spec/sites/inke.md §11 "需要脱敏的字段".
///
/// Anchor and live data (uids, live ids, names, portraits, titles, city)
/// are public and stay (ADR 0009 rule 4). The app API also returns the
/// anchor's precise GPS position and a session token: both replaced. Pull
/// URLs keep `wsABStime` (the expiry, hex seconds); `wsSecret` is replaced.
/// The app's creator objects carry personal profile data beyond what a room
/// card needs (birthday, IP location, real name, last payment date):
/// replaced as well.
/// Session cookies arrive as Set-Cookie and are always scrubbed by the tool.
const ScrubRules inkeRules = ScrubRules(
  jsonKeys: {
    'gps_position': _secret,
    'token': _secret,
    'birth': _secret,
    'verified_birthday': _secret,
    'ip_location': _secret,
    'real_name': _secret,
    'user_last_pay_date': _secret,
  },
  queryParams: {'wsSecret': _secret},
);
