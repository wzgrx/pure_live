import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;

/// Keeps this window's view of the shared data current (docs/TASKS.md/
/// U.13 c14): every desktop window opens the same database, and when
/// another window writes to it, this one takes the change in (settings,
/// sign-ins, follows, history; [LiveStore.syncExternal]).
///
/// Nothing polls: the data folder's change events wake it (the database
/// file and its journal change on every write), and the window coming to
/// the front checks once more. Its own writes cost one small query.
final class SharedDataWatch {
  /// Creates the watch over [_folder], the folder of [_store]'s database.
  new(this._store, this._folder);

  final LiveStore _store;
  final Directory _folder;
  StreamSubscription<FileSystemEvent>? _events;
  Timer? _timer;

  /// How long a burst of file events settles before the check.
  static const Duration settle = Duration(milliseconds: 200);

  /// Starts watching; nothing when the system cannot watch the folder.
  void start() {
    try {
      _events = _folder.watch().listen(
        (event) {
          if (isDatabaseFile(event.path)) _schedule(settle);
        },
        onError: (Object error, StackTrace stack) =>
            log('Shared data watch failed', name: 'Desktop', error: error, stackTrace: stack),
      );
    } on Object catch (error, stack) {
      log('Shared data watch unavailable', name: 'Desktop', error: error, stackTrace: stack);
    }
  }

  /// Checks now (the window came to the front).
  void check() => _schedule(Duration.zero);

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      unawaited(
        _store.syncExternal().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) =>
              log('Shared data sync failed', name: 'Desktop', error: error, stackTrace: stack),
        ),
      );
    });
  }

  /// Stops watching.
  Future<void> dispose() async {
    _timer?.cancel();
    await _events?.cancel();
  }
}

/// Whether [path] is the store's database or its journal.
bool isDatabaseFile(String path) => p.basename(path).startsWith(LiveStore.fileName);
