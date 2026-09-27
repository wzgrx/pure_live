import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// PandaTV: spec/sites/pandalive.md §11 "需要脱敏的字段".
///
/// Broadcasters (ids, nicknames, titles, images) and broadcasts are public
/// and stay (ADR 0009 rule 4). Every response echoes the viewer's address
/// (`userIp`); `live/play` adds the viewer's network (`ispInfo`), a guest
/// session key, the chat and WebRTC tokens, a signed room blob and the IVS
/// playback token in the master URLs, plus the room's top fans (viewers).
/// The IVS master carries the viewer's address and session in its session
/// data and opaque per-session variant paths.
const ScrubRules pandaliveRules = ScrubRules(
  jsonKeys: {'userIp': _secret, 'token': _secret, 'roomInfo': _secret, 'sessKey': _secret},
  jsonPaths: {
    r'$.ispInfo.countryCode': _secret,
    r'$.ispInfo.isp': _secret,
    r'$.ispInfo.organization': _secret,
    r'$.fanList[*].userId': _person,
    r'$.fanList[*].userIdx': _person,
    r'$.fanList[*].userNick': _person,
    r'$.fanList[*].userProfileImg': _secret,
    r'$.fanList[*].userProfileImgHash': _secret,
  },
  queryParams: {'token': _secret},
  textPatterns: {
    'DATA-ID="USER-IP",VALUE="([^"]+)"': _secret,
    'DATA-ID="USER-COUNTRY",VALUE="([^"]+)"': _secret,
    'DATA-ID="SERVING-ID",VALUE="([^"]+)"': _secret,
    'DATA-ID="VIDEO-SESSION-ID",VALUE="([^"]+)"': _secret,
    'DATA-ID="[CE]",VALUE="([^"]+)"': _secret,
    r'/v1/playlist/([A-Za-z0-9_-]{32,})\.m3u8': _secret,
  },
);
