import 'dart:async';

import 'package:live_media/src/input.dart';
import 'package:live_net/live_net.dart';

/// Acquires exactly one input owned by the caller. It observes [cancel] and
/// settles only after releasing anything it acquired before failing.
typedef MediaInputFactory = Future<MediaInput> Function(CancelToken cancel);

/// Hands [input] to the engine (mpv `loadfile` with its headers and proxy).
typedef EngineOpen = Future<void> Function(MediaInput input);

/// The source transaction of one player (3.x's `PlaybackSourceTransport`).
///
/// One input is active at a time. A new open retires anything still being
/// created for an older open; the previous active input is released only
/// after the engine accepted the new one. An engine open that completes
/// after a newer open, [cancelPending] or [close] never makes its input
/// active: the input is released and the open throws [StateError].
final class PlaybackTransport {
  final Set<_Creation> _creating = {};
  final Set<MediaInput> _pending = {};
  final Set<MediaInput> _retiring = {};
  MediaInput? _active;
  int _generation = 0;
  bool _closed = false;
  Future<void>? _closing;

  /// The input the engine plays, if any.
  MediaInput? get active => _active;

  /// Whether the active input can still serve: a closed grant (niconico
  /// seat, FC2 control) means the source must be opened again rather than
  /// its URI replayed.
  bool get activeInputIsUsable => !_closed && (_active?.isUsable ?? false);

  /// Opens a new input with [create] and hands it to the engine with
  /// [engineOpen]; on success it becomes [active] and the previous one is
  /// released.
  Future<void> open(MediaInputFactory create, EngineOpen engineOpen) async {
    if (_closed) throw StateError('Playback transport is closed');
    final generation = ++_generation;
    MediaInput? input;
    bool current() => !_closed && generation == _generation;
    try {
      if (_creating.isNotEmpty || _pending.isNotEmpty || _retiring.isNotEmpty) await _cancelPendingResources();
      if (!current()) throw StateError('Playback input transaction was retired');
      input = await _acquire(create, current);
      if (!current() || !input.isUsable) throw StateError('Playback input transaction was retired');
      await engineOpen(input);
      if (!current() || !input.isUsable) throw StateError('Playback input transaction was retired');
      final previous = _active;
      _active = input;
      _pending.remove(input);
      input = null;
      if (previous != null) await _retire(previous);
    } on Object {
      _pending.remove(input);
      if (input != null) await _retire(input);
      rethrow;
    }
  }

  Future<MediaInput> _acquire(MediaInputFactory create, bool Function() current) async {
    final creation = _Creation();
    _creating.add(creation);
    try {
      final input = await create(creation.cancel);
      _pending.add(input);
      if (!current() || creation.cancel.isCancelled) {
        _pending.remove(input);
        await _retire(input);
        creation.settled.complete();
        throw StateError('Playback input transaction was retired');
      }
      creation.settled.complete();
      return input;
    } catch (error, stack) {
      if (!creation.settled.isCompleted) {
        if (creation.cancel.isCancelled) {
          creation.settled.complete();
        } else {
          creation.settled.completeError(error, stack);
        }
      }
      rethrow;
    } finally {
      _creating.remove(creation);
    }
  }

  /// Cancels only the open in progress; the active input stays until it is
  /// replaced or [close]d. A late creation result is released by its open.
  Future<void> cancelPending() async {
    _generation++;
    await _cancelPendingResources();
  }

  Future<void> _cancelPendingResources() async {
    final creating = _creating.toList();
    for (final creation in creating) {
      creation.cancel.cancel();
    }
    final pending = _pending.toList();
    _pending.clear();
    await Future.wait([
      ...pending.map(_retire),
      ..._retiring.map((input) => input.close()),
      for (final creation in creating) creation.settled.future,
    ]);
  }

  Future<void> _retire(MediaInput input) async {
    _retiring.add(input);
    try {
      await input.close();
    } finally {
      _retiring.remove(input);
    }
  }

  /// Releases everything; later opens throw.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    final active = _active;
    _active = null;
    final pending = cancelPending();
    final activeClose = active == null ? Future<void>.value() : _retire(active);
    await Future.wait([pending, activeClose, ..._retiring.map((input) => input.close())]);
  }
}

final class _Creation {
  new() {
    // open always observes the creation; teardown may join it too.
    unawaited(settled.future.catchError((Object _) {}));
  }

  final cancel = CancelToken();
  final settled = Completer<void>();
}
