import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// Douyu HTTP samples: spec/sites/douyu.md §11 "需要脱敏的字段".
///
/// The danmaku viewer keys (`uid`, `nn`, `ic`, `uat`) are not listed here: in
/// the HTTP bodies the same names carry the streamer's public identity
/// (`mixList`/`allpage` `rl[].nn` and `rl[].uid`), which ADR 0009 rule 4 keeps
/// real. They belong to the danmaku frames, see [douyuDanmakuRules].
const ScrubRules douyuRules = ScrubRules(
  jsonKeys: {
    // Signing material (getEncryption, signed form).
    'key': _secret, 'rand_str': _secret, 'enc_data': _secret, 'auth': _secret,
    'did': _secret, 'dy_did': _secret, 'acf_did': _secret, 'game_did': _secret,
    // Session and account.
    'acf_uid': _person, 'dy_auth': _secret, 'acf_auth': _secret,
    'acf_jwt_token': _secret, 'acf_stk': _secret, 'acf_ltkid': _secret, 'acf_ssid': _secret,
    'LTP0': _secret, 'token': _secret, 'ltkid': _secret, 'stk': _secret,
    // Client network data (getH5PlayV1 `data.client_ip`).
    'ip': _secret, 'client_ip': _secret, 'clientIp': _secret,
    // getH5PlayV1 `data.p2pMeta` repeats the CDN signature of the media URL.
    'txSecret': _secret, 'xp2p_txSecret': _secret,
  },
  queryParams: {
    'did': _secret, 'tt': _secret, 'sign': _secret, 'auth': _secret, 'enc_data': _secret,
    // CDN signatures; the expiry fields (expire, wsTime, txTime) stay real
    // because lease timing is derived from them. `sid` is not one: in
    // getH5PlayV1 `rtmp_live` it is the public show id (`data.show_id`,
    // betard `room.show_id`).
    'wsSecret': _secret, 'wsAuth': _secret, 'txSecret': _secret, 'token': _secret, 'uuid': _secret,
    'origin_sign': _secret, 'uid': _person,
  },
);

/// Douyu danmaku frames (S13): the viewer fields `uid`, `nn`, `ic`, `uat` get
/// one pseudonym per person (spec/sites/douyu.md §11). Kept apart from
/// [douyuRules] for the frame capture tool, which is not built yet.
const ScrubRules douyuDanmakuRules = ScrubRules(
  jsonKeys: {'uid': _person, 'nn': _person, 'ic': _person, 'uat': _person},
);
