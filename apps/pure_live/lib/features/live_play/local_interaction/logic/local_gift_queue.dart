import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_gift_tier.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_interaction.dart';

/// Starts a one-shot timer (a fake one in tests).
typedef LocalOneShotTimer = Timer Function(Duration duration, void Function() done);

/// A gift banner on the picture. [serial] names the banner: a combo's new
/// count (D08.4 c1) is a new [LocalGiftShow] with the same serial and the
/// next [revision], so the banner on the screen stays and only its "×N"
/// jumps.
@immutable
final class LocalGiftShow {
  /// Creates the banner of [message].
  const new(this.message, this.serial, {this.revision = 0});

  /// The gift's message (its count so far).
  final LiveMessage message;

  /// Counts the banners of the room.
  final int serial;

  /// How many times the count went up since the banner was made.
  final int revision;

  /// The gift ([LocalGiftData.of] the message).
  LocalGiftData? get gift => LocalGiftData.of(message);

  /// How many: the combo's count so far.
  int get count => gift?.count ?? 1;

  /// The effect's tier (D08.5 c1; the banner when the message is not a
  /// local gift's).
  LocalGiftTier get tier => gift?.tier ?? LocalGiftTier.medium;

  /// The same banner saying [next] (the combo's new count).
  LocalGiftShow grown(LiveMessage next) => LocalGiftShow(next, serial, revision: revision + 1);
}

/// The room's gift banners (D08.4 c4): one on the picture at a time, for
/// [duration] each (3.x's 3 s), the others waiting in the order they were
/// sent, at most [limit] shown and waiting together; beyond that a gift
/// only joins the chat list. A combo's banner grows where it is ([grow]):
/// on the picture its time starts again, waiting it keeps its place.
///
/// [value] is the banner on the picture now (null: none); listeners hear of
/// every change, a count raised included.
///
/// D08.5 plugs in here: [durationOf] gives a banner (an effect) its own
/// time; the layer draws [value] by its presenter.
final class LocalGiftQueue extends ChangeNotifier implements ValueListenable<LocalGiftShow?> {
  /// Creates an empty queue; [timer] starts the banners' timers (a fake one
  /// in tests).
  new({
    this.duration = const Duration(seconds: 3),
    this.limit = LocalCatalog.giftBannerLimit,
    this.durationOf,
    LocalOneShotTimer? timer,
  }) : _timer = timer ?? Timer.new;

  /// How long a banner stays on the picture.
  final Duration duration;

  /// The most banners shown and waiting together.
  final int limit;

  /// How long a banner stays, when not [duration] (D08.5's effects).
  final Duration Function(LocalGiftShow show)? durationOf;

  final LocalOneShotTimer _timer;
  final List<LocalGiftShow> _waiting = [];
  LocalGiftShow? _current;
  Timer? _clock;
  int _serial = 0;
  bool _disposed = false;

  /// The banner on the picture, or null.
  @override
  LocalGiftShow? get value => _current;

  /// The banners waiting, next first.
  List<LocalGiftShow> get waiting => List.unmodifiable(_waiting);

  /// How many banners are shown and waiting.
  int get length => (_current == null ? 0 : 1) + _waiting.length;

  /// Adds the banner of [message]: on the picture at once when none is,
  /// else at the end of the line. Null (no banner) when [limit] are shown
  /// and waiting already.
  LocalGiftShow? add(LiveMessage message) {
    if (_disposed || length >= limit) return null;
    final show = LocalGiftShow(message, ++_serial);
    if (_current == null) {
      _show(show);
    } else {
      _waiting.add(show);
      notifyListeners();
    }
    return show;
  }

  /// Puts [message] (the combo's new count) in [show]'s banner: on the
  /// picture its time starts again, waiting it keeps its place. Null when
  /// the banner is gone.
  LocalGiftShow? grow(LocalGiftShow show, LiveMessage message) {
    if (_disposed) return null;
    final current = _current;
    if (current != null && current.serial == show.serial) {
      _show(current.grown(message));
      return _current;
    }
    final at = _waiting.indexWhere((waiting) => waiting.serial == show.serial);
    if (at < 0) return null;
    final grown = _waiting[at] = _waiting[at].grown(message);
    notifyListeners();
    return grown;
  }

  /// Takes every banner away.
  void clear() {
    _clock?.cancel();
    _clock = null;
    _waiting.clear();
    if (_current == null) return;
    _current = null;
    if (!_disposed) notifyListeners();
  }

  void _show(LocalGiftShow show) {
    _current = show;
    _clock?.cancel();
    _clock = _timer(durationOf?.call(show) ?? duration, _next);
    notifyListeners();
  }

  void _next() {
    if (_disposed) return;
    _clock = null;
    if (_waiting.isEmpty) {
      _current = null;
      notifyListeners();
    } else {
      _show(_waiting.removeAt(0));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    super.dispose();
  }
}
