import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// Twitch: spec/sites/twitch.md §11 "需要脱敏的字段".
///
/// Streamer public data stays real (ADR 0009 rule 4): logins, ids, names,
/// titles, previews, counts. What identifies this viewer or signs its
/// session is replaced: the playback token's viewer IP, its
/// signature, the usher query and the master playlist's session values.
const ScrubRules twitchRules = ScrubRules(
  jsonKeys: {
    // PlaybackAccessToken: the signature of `value`, and inside `value` (a
    // JSON string, scrubbed as JSON) the viewer's IP. Its `device_id` echoes
    // the random Device-Id header of the capture, kept like the header.
    'signature': _secret, 'user_ip': _secret,
  },
  queryParams: {
    // Usher: the playback token and its signature; the play session.
    'sig': _secret, 'token': _secret, 'play_session_id': _secret,
  },
  textPatterns: {
    // Master playlist (EXT-X-TWITCH-INFO): viewer IP, session ids and the
    // base64 segment URLs `C`/`E` that carry a signed session.
    'USER-IP="([^"]+)"': _secret,
    'SERVING-ID="([^"]+)"': _secret,
    'VIDEO-SESSION-ID="([^"]+)"': _secret,
    '[,:]C="([^"]+)"': _secret,
    '[,:]E="([^"]+)"': _secret,
    // Variant playlists: the signed session is the path segment.
    r'/v1/playlist/([A-Za-z0-9_-]+)\.m3u8': _secret,
  },
);
