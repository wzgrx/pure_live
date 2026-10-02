import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether a recording's file is there, asked off the UI thread (B08 c3,
/// audit B-20; B09 c6). A build calls [saved] with the path it shows and
/// gets the last answer at once (no for a new path); one look at a time
/// runs in the background, and [onChanged] is called when its answer
/// differs (the owner builds again). The live room's record panel and the
/// recording centre's cards both ask through one of these.
final class SavedFileCheck {
  /// Creates the check; [onChanged] is called when the answer changes.
  new(this.onChanged);

  /// Called when the file turns up or goes.
  final VoidCallback onChanged;

  String? _path;
  bool _exists = false;
  bool _looking = false;
  bool _disposed = false;

  /// [path] when its file was there when last looked for, else null; looks
  /// again in the background.
  String? saved(String? path) {
    if (path != _path) {
      _path = path;
      _exists = false;
    }
    _look();
    return _exists ? path : null;
  }

  void _look() {
    final path = _path;
    if (path == null || _looking || _disposed) return;
    _looking = true;
    unawaited(
      // The asynchronous call on purpose: the UI thread does not wait for
      // the disk (B-20).
      // ignore: avoid_slow_async_io
      File(path).exists().then((exists) => exists, onError: (Object _) => false).then((exists) {
        _looking = false;
        if (_disposed) return;
        if (path != _path) {
          _look();
        } else if (exists != _exists) {
          _exists = exists;
          onChanged();
        }
      }),
    );
  }

  /// Stops telling of answers.
  void dispose() => _disposed = true;
}
