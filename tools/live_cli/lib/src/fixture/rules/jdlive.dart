import 'package:live_cli/src/fixture/scrub.dart';

/// JD Live: spec/sites/jdlive.md §11 "需要脱敏的字段".
///
/// The recorded samples are the evidence for the retirement proposal: the
/// public list carries shops' public data (ADR 0009 rule 4 keeps it real);
/// the play request answers an empty 403. Anonymous cookies arrive as
/// Set-Cookie and are always scrubbed by the tool.
const ScrubRules jdliveRules = ScrubRules();
