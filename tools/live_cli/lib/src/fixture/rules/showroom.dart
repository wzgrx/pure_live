import 'package:live_cli/src/fixture/scrub.dart';

/// SHOWROOM: spec/sites/showroom.md §11 "需要脱敏的字段".
///
/// The HTTP samples hold only public room data (ids, names, covers, telops,
/// the shared pull URLs and the per-live comment key every viewer gets);
/// session cookies arrive as Set-Cookie and are always scrubbed by the tool.
/// Viewer data lives in the comment frames (see ShowroomFrameScrubber).
const ScrubRules showroomRules = ScrubRules();
