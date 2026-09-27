import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// Sensitive fields per platform, from the "需要脱敏的字段" list in each
/// `spec/sites/<platform>.md` §11. Cookie headers, Set-Cookie values and
/// Authorization headers are always scrubbed and are not repeated here.
const Map<String, ScrubRules> platformRules = {
  'douyu': ScrubRules(
    jsonKeys: {
      // Signing material (getEncryption, signed form).
      'key': _secret, 'rand_str': _secret, 'enc_data': _secret, 'auth': _secret,
      'did': _secret, 'dy_did': _secret, 'acf_did': _secret, 'game_did': _secret,
      // Session and account.
      'uid': _person, 'acf_uid': _person, 'dy_auth': _secret, 'acf_auth': _secret,
      'acf_jwt_token': _secret, 'acf_stk': _secret, 'acf_ltkid': _secret, 'acf_ssid': _secret,
      'LTP0': _secret, 'token': _secret, 'ltkid': _secret, 'stk': _secret,
      // Client network data.
      'ip': _secret, 'client_ip': _secret, 'clientIp': _secret,
      // Danmaku viewers.
      'nn': _person, 'ic': _person, 'uat': _person,
    },
    queryParams: {
      'did': _secret, 'tt': _secret, 'sign': _secret, 'auth': _secret, 'enc_data': _secret,
      // CDN signatures; the expiry fields (expire, wsTime, txTime) stay real
      // because lease timing is derived from them.
      'wsSecret': _secret, 'txSecret': _secret, 'token': _secret, 'uuid': _secret,
      'sid': _secret, 'origin_sign': _secret, 'uid': _person,
    },
  ),
};
