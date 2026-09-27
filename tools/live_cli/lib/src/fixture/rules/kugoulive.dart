import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// Kugou Live (Fanxing): spec/sites/kugoulive.md §11 "需要脱敏的字段".
///
/// Streamer public data (room id, kugou id, user id, names, covers, counts)
/// stays real (ADR 0009 rule 4). Media URLs carry a Tencent signature
/// (`txSecret`) and a signed `token`; both are replaced, `txTime` (the hex
/// expiry) stays real for lease tests.
const ScrubRules kugouliveRules = ScrubRules(queryParams: {'txSecret': _secret, 'token': _secret});
