/// Recording core of Pure Live (docs/modules/M8-record.md): record tasks
/// and their queue, stream selection, inputs through live_media's loopback
/// relay, FFmpeg capture into clock-v1 segments and their MP4 join behind
/// an injected [FfmpegRunner], retries, lease renewal, live checks,
/// persistence and restore. Pure Dart.
library;

import 'package:live_record/src/ffmpeg.dart';

export 'src/capture.dart';
export 'src/chat.dart';
export 'src/diagnostics.dart';
export 'src/ffmpeg.dart';
export 'src/input.dart';
export 'src/merge.dart';
export 'src/metrics.dart';
export 'src/naming.dart';
export 'src/policy.dart';
export 'src/recorder.dart';
export 'src/resolver.dart';
export 'src/scheduler.dart';
export 'src/segments.dart';
export 'src/settings.dart';
export 'src/storage.dart';
export 'src/task.dart';
