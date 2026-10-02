import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:pure_live/routes/route_observer.dart';

/// The prompts the app shows by itself, not from a tap, in the order they
/// go first when several wait (docs/T07/T07i/T07i.2 c7).
enum AppPromptKind {
  /// "打开分享的直播间": a share code was found on the clipboard (U.3d).
  share,

  /// "发现新版本": the start-up update check (U.3d).
  update,
}

/// Shows the prompts of [AppPromptKind] one at a time (U.3c c7; 3.x let the
/// share prompt and the update prompt open over each other).
///
/// A prompt waits while another one is open; among waiting prompts the
/// share prompt goes first. A prompt may also wait for a moment of its own
/// ([show]'s `ready`, e.g. the update prompt waits until home is on top):
/// readiness is checked again after every page or dialog change
/// ([liveRouteObserver]) and a frame after a prompt closes, so a room the
/// share prompt opened is on top before the next prompt looks.
final class AppPrompts {
  /// A queue; the app uses [instance].
  new({ValueChanged<void Function(RouteEvent)>? listenRoutes}) {
    (listenRoutes ?? liveRouteObserver.addListener)((_) => _schedule());
  }

  /// The app's queue.
  static final AppPrompts instance = AppPrompts();

  final List<_Waiting<Object?>> _waiting = [];
  int _sequence = 0;
  bool _showing = false;
  bool _scheduled = false;

  /// Whether a prompt is open.
  bool get isShowing => _showing;

  /// How many prompts wait.
  int get waiting => _waiting.length;

  /// Runs [present] (which shows the prompt and completes when it closes)
  /// once no other prompt is open, no prompt of an earlier kind waits, and
  /// [ready] (when given) says yes; completes with its result.
  Future<T?> show<T>(AppPromptKind kind, Future<T?> Function() present, {bool Function()? ready}) {
    final waiting = _Waiting<T>(kind, _sequence++, present, ready);
    _waiting
      ..add(waiting)
      ..sort((a, b) => a.kind.index != b.kind.index ? a.kind.index - b.kind.index : a.sequence - b.sequence);
    _pump();
    return waiting.done.future;
  }

  /// Checks the waiting prompts again (when their moment may have come).
  void recheck() => _schedule();

  /// Drops every waiting prompt (they complete with null).
  void clear() {
    for (final waiting in _waiting) {
      waiting.done.complete();
    }
    _waiting.clear();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // Never inside a navigator's update: the route events come from there.
    scheduleMicrotask(() {
      _scheduled = false;
      _pump();
    });
  }

  void _pump() {
    if (_showing) return;
    final next = _waiting.where((waiting) => waiting.isReady).firstOrNull;
    if (next == null) return;
    _waiting.remove(next);
    _showing = true;
    unawaited(_run(next));
  }

  Future<void> _run(_Waiting<Object?> waiting) async {
    try {
      waiting.done.complete(await waiting.present());
    } on Object catch (error, stack) {
      waiting.done.completeError(error, stack);
    }
    // A frame for what the prompt started (a room it opened) to be on top.
    await SchedulerBinding.instance.endOfFrame;
    _showing = false;
    _pump();
  }
}

final class _Waiting<T> {
  new(this.kind, this.sequence, this.present, this.ready);

  final AppPromptKind kind;
  final int sequence;
  final Future<T?> Function() present;
  final bool Function()? ready;
  final Completer<T?> done = Completer<T?>();

  bool get isReady => ready?.call() ?? true;
}
