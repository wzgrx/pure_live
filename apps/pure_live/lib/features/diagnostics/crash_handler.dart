import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pure_live_app/features/diagnostics/app_log.dart';

/// Sends uncaught errors to the local log (F-BAK-02, F-NEW-11).
///
/// Nothing is reported anywhere: an uncaught error leaves a marker file next
/// to the log, and when the user turned on "崩溃报告" the next launch offers to
/// export a diagnostics bundle (see `CrashMarker`). There is no remote
/// endpoint.
void installCrashHandlers(AppLog log) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    log.error('flutter', details.exceptionAsString(), null, details.stack);
    if (!details.silent) CrashMarker(log).mark();
    previous?.call(details);
  };
  final dispatcher = PlatformDispatcher.instance;
  final previousDispatcher = dispatcher.onError;
  dispatcher.onError = (error, stack) {
    log.error('uncaught', error.runtimeType.toString(), error, stack);
    CrashMarker(log).mark();
    return previousDispatcher?.call(error, stack) ?? true;
  };
}

/// The "an uncaught error happened" marker next to the log.
final class CrashMarker {
  /// Uses [log]'s directory; an in-memory log has no marker.
  const new(this.log);

  /// The log.
  final AppLog log;

  File? get _file {
    final directory = log.directory;
    return directory == null ? null : File('${directory.path}${Platform.pathSeparator}crash.pending');
  }

  /// Records that an uncaught error happened now.
  void mark() {
    try {
      _file?.writeAsStringSync(DateTime.now().toUtc().toIso8601String());
    } on FileSystemException {
      // The log line is still there.
    }
  }

  /// Whether an error happened since the last [take], and clears the marker.
  bool take() {
    final file = _file;
    if (file == null) return false;
    try {
      if (!file.existsSync()) return false;
      file.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
