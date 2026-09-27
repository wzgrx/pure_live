import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// TikTok LIVE: spec/sites/tiktok.md §11 "需要脱敏的字段".
///
/// Streamers' public data (usernames, user and room ids, nicknames,
/// titles, counts) stays real (ADR 0009 rule 4). Media URLs carry a CDN
/// signature (`sign`), image URLs an `x-signature`; a room's push URLs
/// would carry the streamer's stream key. The `stream_data` fields hold
/// JSON inside a string, which query rules cannot reach: the capture
/// script replaces the signatures there afterwards and records it in
/// meta.json.
const ScrubRules tiktokRules = ScrubRules(
  jsonKeys: {'push_urls': _secret, 'complete_push_urls': _secret, 'rtmp_push_url': _secret},
  queryParams: {'sign': _secret, 'x-signature': _secret},
);
