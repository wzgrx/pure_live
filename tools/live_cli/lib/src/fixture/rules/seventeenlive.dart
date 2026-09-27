import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;
const ScrubRule _person = ScrubRule.person;

/// 17LIVE: spec/sites/17live.md §11 "需要脱敏的字段".
///
/// Streamers, their rooms, events, clans and gifts are public and stay
/// (ADR 0009 rule 4); pull URLs carry no signature. A room's guardian is a
/// viewer (the top supporter): id and picture replaced. The messenger token
/// (chat credentials) is a secret wherever it is recorded.
const ScrubRules seventeenliveRules = ScrubRules(
  jsonKeys: {'guardianUserID': _person, 'guardianPicture': _secret},
  jsonPaths: {r'$.token': _secret},
);
