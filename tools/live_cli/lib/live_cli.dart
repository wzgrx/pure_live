/// Pure Live's command-line probe and patrol (docs/E-直播平台/E07-平台巡检):
/// real-network checks of the platform adapters, run by hand and never in
/// the gate (D-017).
library;

export 'src/patrol/checks.dart';
export 'src/patrol/danmaku.dart';
export 'src/patrol/media.dart';
export 'src/patrol/patrol_command.dart';
export 'src/patrol/report.dart';
export 'src/patrol/result.dart';
export 'src/patrol/targets.dart';
export 'src/probe/probe_command.dart';
export 'src/sites.dart';
