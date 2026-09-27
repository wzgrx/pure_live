import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// Kuaishou: spec/sites/kuaishou.md §11 "需要脱敏的字段".
///
/// Streamer public data stays real (ADR 0009 rule 4): the author id used as
/// the room id, name, avatar, description, liveStreamId, and `originUserId`
/// (the streamer's numeric uid; custom ids embed it verbatim, e.g. `KPL` + uid,
/// so it cannot be replaced without leaking through the kept room id).
/// Anonymous-session cookies (did, clientid, client_key, kpn,
/// kuaishou.live.bfb1s) arrive as Set-Cookie and are always scrubbed by the
/// tool; the page state repeats `did` (pcConfig.did).
const ScrubRules kuaishouRules = ScrubRules(
  jsonKeys: {
    // Session material echoed into page state or JSON bodies.
    'did': _secret, 'client_key': _secret, 'token': _secret, 'authToken': _secret,
    // Search session id: base64 of a timestamp and the keyword.
    'ussid': _secret,
    // Internal server hostname in search/error bodies (spec §11: remove).
    'host-name': _secret,
    // Feed viewers (spec §11); on room pages these are the system notice's
    // sender in liveroom.noticeList.
    'userName': _person, 'userId': _person,
  },
  queryParams: {
    // CDN signatures; txTime/wsTime/hwTime/ty_Time stay real for lease timing.
    'txSecret': _secret, 'wsSecret': _secret, 'hwSecret': _secret, 'ty_Secret': _secret, 'stat': _secret,
    // ali-origin (not in the spec table): auth_key = {expiry}-0-0-{md5}; the
    // whole value is replaced, so its embedded expiry is synthetic.
    'auth_key': _secret,
    // Session parameters.
    'did': _secret, 'lssid': _secret,
  },
  responseHeaders: {
    // Every live.kuaishou.com response echoes the caller's public IP.
    'x-ksclient-ip': _secret,
  },
);
