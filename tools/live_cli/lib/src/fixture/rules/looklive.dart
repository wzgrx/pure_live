import 'package:live_cli/src/fixture/scrub.dart';

/// LOOK Live (NetEase): spec/sites/looklive.md §11 "需要脱敏的字段".
///
/// The recommendation lists and the room endpoint only carry anchors'
/// public data (ADR 0009 rule 4 keeps it real). The request form is the
/// `weapi` envelope of a public payload under fixed web keys, so it is no
/// credential; the anonymous `NMTID` cookie arrives as Set-Cookie and is
/// always scrubbed by the tool.
const ScrubRules lookliveRules = ScrubRules();
