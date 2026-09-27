import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// Douyin: spec/sites/douyin.md §11 "需要脱敏的字段".
///
/// `signature` is only a URL parameter here (danmaku handshake signing): as a
/// JSON key it is the streamer's public bio, which the legacy parser reads.
const ScrubRules douyinRules = ScrubRules(
  jsonKeys: {
    // Anonymous visitor identity issued with ttwid (`odin` in page state).
    'user_unique_id': _secret, 'user_id': _person,
    // Account identity; sec_uid also keys viewers in danmaku.
    'sec_uid': _person,
    // Cookies and signing material, when a page embeds them.
    'ttwid': _secret, 'UIFID_TEMP': _secret, 'UIFID': _secret, 'odin_tt': _secret,
    'sessionid': _secret, 'sessionid_ss': _secret, 'sid_tt': _secret, 'sid_guard': _secret,
    'uid_tt': _secret, 'uid_tt_ss': _secret, 'passport_csrf_token': _secret, 's_v_web_id': _secret,
    'msToken': _secret, 'a_bogus': _secret, 'X-Bogus': _secret,
    '__ac_nonce': _secret, '__ac_signature': _secret,
    // Stream-level secret in live_core_sdk_data.pull_data.stream_data.common.
    'secret_key': _secret,
  },
  queryParams: {
    // Request signing and visitor identity.
    'a_bogus': _secret, 'X-Bogus': _secret, 'msToken': _secret, 'signature': _secret,
    'verifyFp': _secret, 'fp': _secret, '__ac_signature': _secret,
    'user_unique_id': _secret, 'did': _secret, 'iid': _secret, 'device_id': _secret,
    'sec_user_id': _person,
    // CDN signatures on play and image URLs. Expiry fields (expire, volcTime,
    // wsTime, keeptime, x-expires) stay real because lease timing is derived
    // from them; auth_key embeds its own timestamp but is one opaque value.
    'sign': _secret, 'unique_id': _secret, 'volcSecret': _secret, 'wsSecret': _secret,
    'txSecret': _secret, 'auth_key': _secret, '_neptune_token': _secret,
    'x-signature': _secret, 'x-orig-sign': _secret,
  },
  // Server-issued visitor tokens echoed in response headers; the risk-control
  // headers are JSON and only their `detail` blob identifies the visitor.
  responseHeaders: {
    'x-ms-token': _secret,
    'cookie_ttwidinfo_webid': _secret,
    'bdturing-verify': _secret,
    'x-vc-bdturing-parameters': _secret,
  },
  jsonPaths: {r'$header.bdturing-verify.detail': _secret, r'$header.x-vc-bdturing-parameters.detail': _secret},
);
