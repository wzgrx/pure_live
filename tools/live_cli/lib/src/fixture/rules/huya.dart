import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// Huya: spec/sites/huya.md §11 "脱敏".
///
/// Streamer public data stays real (ADR 0009 rule 4): room id, anchor uid
/// (`profileInfo.uid`, `lPresenterUid`, search `uid`), yyid, lChannelId,
/// lSubChannelId, CDN type and host, stream name, heat, area. `wsTime` stays
/// real because lease timing is derived from it (spec §6.6). Cookie and
/// Set-Cookie values (yyuid, udb_*) are always scrubbed by the tool.
///
/// Not expressible with the current scrubber, so recorded differently from §11:
/// - `fm` should become a synthetic template that keeps its base64 form and the
///   `$0`-`$3` placeholders; the scrubber can only substitute characters, so the
///   scrubbed value is no longer a decodable template.
/// - The anonymous-login uid shares the key `uid` with the public anchor uid, so
///   it cannot be scrubbed by key without also scrubbing the anchor.
const ScrubRules huyaRules = ScrubRules(
  jsonKeys: {
    // Viewer identity: account yyuid and the Tars tId (HuyaUserId) fields.
    'yyuid': _person, 'sGuid': _secret, 'sCookie': _secret, 'sToken': _secret,
    // Anonymous-login session token.
    'biztoken': _secret,
  },
  queryParams: {
    // AntiCode signing material: `fm` is the server signing template and
    // `wsSecret` the signature (room, native and web WUP tokens alike).
    'fm': _secret, 'wsSecret': _secret,
    // Values derived from the viewer: seqid = viewer uid + ms, u = rotated
    // viewer uid, uid/uuid on the WAP form, yyuid from an account cookie.
    'seqid': _secret, 'u': _person, 'uid': _person, 'uuid': _secret, 'yyuid': _person,
    // Other signing material seen in recorded bodies (ADR 0009 rule 4, spec
    // §6.7): the REPLAY VOD m3u8 in liveData.hls/hlsUrl carries `srckey`, and
    // tx-live-cover screenshots carry a COS `sign` (HMAC plus a cloud SecretId).
    // The cover path itself stays real.
    'srckey': _secret, 'sign': _secret,
  },
);
