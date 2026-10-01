import 'dart:math';

/// How the queue moves on (pure_live_TV `MusicPlayMode`).
enum PlayMode {
  /// In order; music wraps to the start after the last item.
  sequence,

  /// The current item again when it ends; manual next still moves on.
  repeatOne,

  /// A shuffled order that plays every item once before reshuffling.
  shuffle;

  /// The mode the mode button switches to.
  PlayMode get next => switch (this) {
    sequence => repeatOne,
    repeatOne => shuffle,
    shuffle => sequence,
  };
}

/// What [PlayQueue.playNext] did.
enum PlayNextResult {
  /// Added after the current item.
  inserted,

  /// Was elsewhere in the queue; moved after the current item.
  moved,

  /// Already next; nothing changed.
  alreadyNext,

  /// The queue was empty; it is now the only (current) item.
  started,
}

/// The play queue of music mode and of multi-part videos, without the
/// player (pure_live_TV `b9d2f739` `music_player_controller.dart`'s queue and
/// advance rules).
///
/// Changes from the TV controller:
/// - shuffle walks a shuffled order (every item once, then a new order whose
///   first item is not the one just played) instead of a fresh random pick
///   each time, which could repeat a song soon and made "previous" jump to
///   the neighbour in list order;
/// - "previous" in shuffle goes back along the shuffled order;
/// - consecutive failures stop after min(queue length, 5) like the TV
///   controller, counted here so the player layer stays thin.
final class PlayQueue<T> {
  /// Creates an empty queue; [idOf] gives an item's identity (a track id).
  new({required this.idOf, this.wrap = true, this._mode = PlayMode.sequence, Random? random})
    : _random = random ?? Random();

  /// Identity of an item; equal ids are the same item.
  final String Function(T item) idOf;

  /// Whether [next] after the last item goes to the first (music) or ends
  /// (a video's parts).
  bool wrap;

  final Random _random;
  final List<T> _items = [];
  var _index = -1;
  PlayMode _mode;
  List<int> _order = [];
  var _failures = 0;

  /// Items in list order.
  List<T> get items => List.unmodifiable(_items);

  /// Index of the current item, -1 when none.
  int get index => _index;

  /// The current item.
  T? get current => _index >= 0 && _index < _items.length ? _items[_index] : null;

  /// Whether the queue has items.
  bool get isNotEmpty => _items.isNotEmpty;

  /// The mode.
  PlayMode get mode => _mode;

  set mode(PlayMode value) {
    if (value == _mode) return;
    _mode = value;
    if (value == PlayMode.shuffle) _reshuffle(keepCurrentFirst: true);
  }

  /// Replaces the queue and starts at [start].
  void replace(Iterable<T> items, {int start = 0}) {
    _items
      ..clear()
      ..addAll(_unique(items));
    _index = _items.isEmpty ? -1 : start.clamp(0, _items.length - 1);
    _failures = 0;
    _reshuffle(keepCurrentFirst: true);
  }

  Iterable<T> _unique(Iterable<T> items) {
    final seen = <String>{};
    return items.where((item) => seen.add(idOf(item)));
  }

  int _find(T item) {
    final id = idOf(item);
    return _items.indexWhere((other) => idOf(other) == id);
  }

  /// Puts [item] right after the current one.
  PlayNextResult playNext(T item) {
    if (_items.isEmpty) {
      replace([item]);
      return PlayNextResult.started;
    }
    final existing = _find(item);
    if (existing >= 0 && existing == _index + 1) return PlayNextResult.alreadyNext;
    if (existing == _index) return PlayNextResult.alreadyNext;
    if (existing >= 0) {
      _items.removeAt(existing);
      if (existing < _index) _index--;
    }
    _items.insert(_index + 1, item);
    _reshuffle(keepCurrentFirst: true, upNext: _index + 1);
    return existing >= 0 ? PlayNextResult.moved : PlayNextResult.inserted;
  }

  /// Adds [item] at the end; false when it is already queued. An empty
  /// queue starts with it.
  bool enqueue(T item) {
    if (_find(item) >= 0) return false;
    _items.add(item);
    if (_index < 0) _index = 0;
    if (_mode == PlayMode.shuffle) {
      // Somewhere in the part of the order still to come.
      final at = _order.indexOf(_index) + 1 + _random.nextInt(_order.length - _order.indexOf(_index));
      _order.insert(at.clamp(0, _order.length), _items.length - 1);
    } else {
      _order.add(_items.length - 1);
    }
    return true;
  }

  /// Removes the item at [position]. Returns whether the current item
  /// changed (the next one takes its place; the queue may be empty).
  bool removeAt(int position) {
    if (position < 0 || position >= _items.length) return false;
    final wasCurrent = position == _index;
    _items.removeAt(position);
    _order = [
      for (final i in _order)
        if (i > position) i - 1 else if (i < position) i,
    ];
    if (_items.isEmpty) {
      _index = -1;
    } else if (wasCurrent) {
      _index = position.clamp(0, _items.length - 1);
    } else if (position < _index) {
      _index--;
    }
    return wasCurrent;
  }

  /// Moves the item at [from] to [to] (list order).
  void move(int from, int to) {
    if (from < 0 || from >= _items.length || to < 0 || to >= _items.length || from == to) return;
    final currentId = current == null ? null : idOf(current as T);
    final orderIds = [for (final i in _order) idOf(_items[i])];
    _items.insert(to, _items.removeAt(from));
    if (currentId != null) _index = _items.indexWhere((item) => idOf(item) == currentId);
    _order = [for (final id in orderIds) _items.indexWhere((item) => idOf(item) == id)];
  }

  /// Makes [position] current.
  bool jumpTo(int position) {
    if (position < 0 || position >= _items.length) return false;
    _index = position;
    return true;
  }

  /// The index [next] would go to, without moving.
  int? peekNext({bool auto = false}) {
    if (_items.isEmpty) return null;
    if (auto && _mode == PlayMode.repeatOne) return _index;
    if (_mode == PlayMode.shuffle) {
      final at = _order.indexOf(_index);
      if (at + 1 < _order.length) return _order[at + 1];
      return wrap || !auto ? -1 : null; // -1: a new order is needed.
    }
    if (_index + 1 < _items.length) return _index + 1;
    return wrap || !auto ? 0 : null;
  }

  /// Moves on. [auto] is true when the current item ended by itself:
  /// repeat-one then stays, and without [wrap] the end of the list stops
  /// (null). Manual next always moves. Returns the new index.
  int? next({bool auto = false}) {
    final target = peekNext(auto: auto);
    if (target == null) return null;
    if (target == -1) {
      _reshuffle(keepCurrentFirst: false, avoidFirst: _index);
      return _index = _order.first;
    }
    return _index = target;
  }

  /// Moves back: list order, or back along the shuffled order; wraps to the
  /// end from the first item.
  int? previous() {
    if (_items.isEmpty) return null;
    if (_mode == PlayMode.shuffle) {
      final at = _order.indexOf(_index);
      _index = _order[(at - 1 + _order.length) % _order.length];
    } else {
      _index = (_index - 1 + _items.length) % _items.length;
    }
    return _index;
  }

  /// The current item opened: the failure count starts over.
  void opened() => _failures = 0;

  /// The current item failed to open or play. Returns the index to try
  /// next, or null when min(length, 5) items failed in a row (stop: a dead
  /// network must not spin the queue forever).
  int? failed() {
    _failures++;
    if (_items.isEmpty || _failures >= _items.length.clamp(1, 5)) return null;
    return next();
  }

  void _reshuffle({required bool keepCurrentFirst, int? upNext, int? avoidFirst}) {
    final all = List<int>.generate(_items.length, (i) => i);
    if (_mode != PlayMode.shuffle) {
      _order = all;
      return;
    }
    all.shuffle(_random);
    if (keepCurrentFirst && _index >= 0) {
      all
        ..remove(_index)
        ..insert(0, _index);
      if (upNext != null && upNext != _index) {
        all
          ..remove(upNext)
          ..insert(1, upNext);
      }
    } else if (avoidFirst != null && all.length > 1 && all.first == avoidFirst) {
      all.add(all.removeAt(0));
    }
    _order = all;
  }
}
