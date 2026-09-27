import 'dart:async';
import 'dart:collection';

import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/pipeline/filters.dart';
import 'package:live_danmaku/src/pipeline/sampler.dart';
import 'package:live_danmaku/src/pipeline/settings.dart';
import 'package:live_danmaku/src/transport.dart';
import 'package:meta/meta.dart';

/// What the UI isolate receives (CONN-2): one batch per ≥ 16 ms, at most
/// 64 ms after the previous one while messages arrive.
@immutable
final class DanmakuBatch {
  /// Creates a batch.
  const new({
    required this.room,
    required this.session,
    this.list = const [],
    this.screen = const [],
    this.gifts = const [],
    this.superChats = const [],
    this.online = const {},
    this.system = const [],
    this.dropped = 0,
  });

  /// `platform:roomId`.
  final String room;

  /// Session token.
  final int session;

  /// Chat for the list, oldest first, after filtering (at most 200).
  final List<DanmakuChat> list;

  /// Screen candidates after sampling (a subset of [list] plus local
  /// messages).
  final List<DanmakuChat> screen;

  /// Gifts for the list (LST-8), after the user block list.
  final List<DanmakuGift> gifts;

  /// New super chats (deduplicated by the §1 equality).
  final List<DanmakuSuperChat> superChats;

  /// Latest figure per kind (LST-6).
  final Map<AudienceKind, int> online;

  /// Status notices.
  final List<DanmakuSystem> system;

  /// Messages dropped by the per-batch caps in this batch.
  final int dropped;

  /// Whether the batch carries nothing.
  bool get isEmpty =>
      list.isEmpty && screen.isEmpty && gifts.isEmpty && superChats.isEmpty && online.isEmpty && system.isEmpty;
}

/// The background half of spec §2–§4 for one session: filter chain,
/// sampling and batching. Runs wherever events are decoded (the worker
/// isolate); only [DanmakuBatch]es leave it.
final class DanmakuPipeline {
  /// Creates the pipeline for [room] and [session]; [onBatch] receives the
  /// batches.
  new({
    required this.room,
    required this.session,
    required this.onBatch,
    DanmakuFilterSettings settings = const DanmakuFilterSettings(),
    DanmakuScreenBudget? budget,
    DanmakuClock? clock,
    this.interval = const Duration(milliseconds: 64),
    this.early = const Duration(milliseconds: 16),
    this.maxList = 200,
    this.maxGifts = 50,
  }) : _settings = settings,
       _blocks = DanmakuBlockList(users: settings.blockedUsers, words: settings.blockedWords),
       budget = budget ?? DanmakuScreenBudget.room,
       _clock = clock ?? const SystemDanmakuClock() {
    _lastFlush = _clock.micros() - interval.inMicroseconds;
  }

  /// `platform:roomId`.
  final String room;

  /// Session token.
  final int session;

  /// Receives each batch.
  final void Function(DanmakuBatch batch) onBatch;

  /// Longest wait after the previous batch while messages are pending.
  final Duration interval;

  /// Shortest wait after the first pending message.
  final Duration early;

  /// List cap per batch (oldest dropped first).
  final int maxList;

  /// Gift cap per batch (oldest dropped first).
  final int maxGifts;

  final DanmakuClock _clock;
  DanmakuFilterSettings _settings;
  DanmakuBlockList _blocks;

  /// SMP-3 the surface's current screen budget; the UI isolate updates it.
  DanmakuScreenBudget budget;

  final DanmakuGate _gate = DanmakuGate();
  final RepeatFilter _repeats = RepeatFilter();
  final SimilarityFilter _similar = SimilarityFilter();
  final DensitySampler _sampler = DensitySampler();
  final LinkedHashSet<DanmakuSuperChat> _seenSuperChats = LinkedHashSet();

  final Queue<DanmakuChat> _list = Queue();
  final List<DanmakuChat> _local = [];
  final Queue<DanmakuGift> _gifts = Queue();
  final List<DanmakuSuperChat> _superChats = [];
  final Map<AudienceKind, int> _online = {};
  final List<DanmakuSystem> _system = [];
  var _dropped = 0;
  late int _lastFlush;
  Timer? _timer;
  var _closed = false;

  /// Current settings.
  DanmakuFilterSettings get settings => _settings;

  /// FLT-6 applies [value] to the next message; pending lines that the new
  /// block list matches are removed (FLT-2).
  set settings(DanmakuFilterSettings value) {
    _settings = value;
    _blocks = DanmakuBlockList(users: value.blockedUsers, words: value.blockedWords);
    _list.removeWhere(_blocks.matches);
    _gifts.removeWhere(_blocks.matches);
    if (!value.mergeRepeats) _repeats.clear();
    if (!value.similarity) _similar.clear();
  }

  /// Runs [event] through the chain and queues it.
  void add(DanmakuEvent event) {
    if (_closed || event.room != room || event.session != session) return;
    switch (event) {
      case DanmakuChat():
        if (event.isLocal) {
          _local.add(event);
        } else {
          if (!_accepts(event)) return;
          _list.add(event);
          if (_list.length > maxList) {
            _list.removeFirst();
            _dropped++;
          }
        }
      case DanmakuGift():
        if (!event.isLocal && _blocks.matches(event)) return;
        _gifts.add(event);
        if (_gifts.length > maxGifts) {
          _gifts.removeFirst();
          _dropped++;
        }
      case DanmakuSuperChat():
        if (!_seenSuperChats.add(event)) return;
        if (_seenSuperChats.length > 512) _seenSuperChats.remove(_seenSuperChats.first);
        _superChats.add(event);
      case DanmakuOnline(:final audience, :final value):
        _online[audience] = value;
      case DanmakuSystem():
        _system.add(event);
    }
    _schedule();
  }

  /// §3 the filter chain, cheapest first: gate, block list, bots, repeats,
  /// similarity.
  bool _accepts(DanmakuChat chat) {
    final now = _clock.now();
    if (!_gate.accepts(chat, now)) return false;
    if (_blocks.matches(chat)) return false;
    final settings = _settings;
    if (settings.hideSuspectedBots && chat.suspectedBot) return false;
    if (settings.mergeRepeats && !_repeats.accepts(chat.text, now, settings.repeatWindow)) return false;
    if (settings.similarity &&
        !_similar.accepts(
          chat.text,
          now,
          threshold: settings.similarityThreshold,
          window: settings.similarityWindow,
          capacity: settings.similarityCacheSize,
        )) {
      return false;
    }
    return true;
  }

  void _schedule() {
    if (_timer != null || _closed) return;
    final since = Duration(microseconds: _clock.micros() - _lastFlush);
    var wait = interval - since;
    if (wait < early) wait = early;
    _timer = Timer(wait, flush);
  }

  /// Sends what is pending now.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_closed) return;
    final now = _clock.micros();
    final elapsed = Duration(microseconds: now - _lastFlush);
    _lastFlush = now;
    final list = [..._list];
    final picked = _sampler.pick(list.length, elapsed, budget.perSecond);
    final batch = DanmakuBatch(
      room: room,
      session: session,
      list: [...list, ..._local],
      screen: [for (final index in picked) list[index], ..._local],
      gifts: [..._gifts],
      superChats: [..._superChats],
      online: {..._online},
      system: [..._system],
      dropped: _dropped,
    );
    _list.clear();
    _local.clear();
    _gifts.clear();
    _superChats.clear();
    _online.clear();
    _system.clear();
    _dropped = 0;
    if (!batch.isEmpty || batch.dropped > 0) onBatch(batch);
  }

  /// Forgets the duplicate, repeat and similarity caches (CONN-4 room
  /// change) and the pending messages.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _gate.clear();
    _repeats.clear();
    _similar.clear();
    _sampler.reset();
    _seenSuperChats.clear();
    _list.clear();
    _local.clear();
    _gifts.clear();
    _superChats.clear();
    _online.clear();
    _system.clear();
    _dropped = 0;
  }

  /// Sends what is pending and stops.
  void close() {
    if (_closed) return;
    flush();
    _closed = true;
  }
}
