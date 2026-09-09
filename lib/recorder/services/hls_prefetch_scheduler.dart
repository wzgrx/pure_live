import 'dart:async';
import 'dart:convert';

import 'hls_prefetch_pool.dart';
import 'hls_retained_manifest.dart';
import 'hls_retained_window.dart';

enum HlsPrefetchResourceKind { media, initialization, key }

final class HlsPrefetchResource {
  HlsPrefetchResource._(this.key, this.uri, this.range, this.kind, [this.feedId, this.sequence]);
  factory HlsPrefetchResource.media(String feedId, HlsSegmentDescriptor segment) => HlsPrefetchResource._(
    jsonEncode(['media', feedId, segment.sequence, segment.uri.toString(), segment.range?.identity]),
    segment.uri,
    segment.range,
    HlsPrefetchResourceKind.media,
    feedId,
    segment.sequence,
  );
  factory HlsPrefetchResource.initialization(HlsMapDescriptor map) => HlsPrefetchResource._(
    jsonEncode(['map', map.identity]),
    map.uri,
    map.range,
    HlsPrefetchResourceKind.initialization,
  );
  factory HlsPrefetchResource.key(HlsKeyDescriptor key) =>
      HlsPrefetchResource._(jsonEncode(['key', key.identity]), key.uri!, null, HlsPrefetchResourceKind.key);
  final String key;
  final Uri uri;
  final HlsSegmentRange? range;
  final HlsPrefetchResourceKind kind;
  final String? feedId;
  final int? sequence;
}

/// One recording source generation, one shared pool, explicitly selected media
/// feeds only. Playlist refresh is independent of native fragment consumption.
/// This owner never selects a different quality or follows a master on its own.
final class HlsPrefetchScheduler {
  HlsPrefetchScheduler({
    required this.pool,
    required this.fetchSnapshot,
    required this.loadResource,
    this.onCoverageGap,
    this.onDownloadResult,
    this.pollInterval,
    this.maximumFeeds = 2,
    this.maximumSegments = 64,
  }) {
    if (maximumFeeds < 1 ||
        maximumFeeds > 2 ||
        maximumSegments < 2 ||
        maximumSegments > 64 ||
        (pollInterval != null && (pollInterval! <= Duration.zero || pollInterval! > const Duration(seconds: 30)))) {
      throw ArgumentError('Invalid recording prefetch scheduling limits');
    }
  }
  final HlsPrefetchPool pool;
  final Future<HlsMediaSnapshot> Function(Uri source, HlsPrefetchCancellation cancellation) fetchSnapshot;
  final Future<HlsPrefetchResponse> Function(HlsPrefetchResource resource, HlsPrefetchCancellation cancellation)
  loadResource;
  final void Function()? onCoverageGap;
  final void Function(HlsPrefetchResource resource, bool ready)? onDownloadResult;
  final Duration? pollInterval;
  final int maximumFeeds;
  final int maximumSegments;
  final Map<String, _Feed> _feeds = {};
  final Map<String, (HlsPrefetchResource, HlsPrefetchTicket, String)> _items = {};
  final Set<Future<void>> _jobs = {};
  bool _finishing = false;
  bool _stopped = false;
  bool _closed = false;
  bool _gap = false;
  Future<void>? _closing;
  int _nextFeed = 0;
  Completer<void> _changed = Completer<void>();

  bool get coverageIncomplete => _gap;
  int get feedCount => _feeds.length;
  int get resourceRecordCount => _items.length;
  bool hasFeed(String id) => _feeds.containsKey(id);
  Set<String> get requiredKeys => {
    for (final feed in _feeds.values) ...feed.wanted.keys,
    for (final feed in _feeds.values)
      for (final generation in feed.published)
        for (final resource in _dependencies(feed.id, generation.where((s) => s.sequence >= feed.delivered - 1)))
          resource.key,
  };

  /// Unsupported inputs remain with the caller's original path. No network is
  /// started until the complete initial metadata/render contract is accepted.
  bool select(String id, Uri fetchSource, HlsMediaSnapshot initial) {
    if (_closed || _finishing || _feeds.containsKey(id) || _feeds.length >= maximumFeeds) return false;
    final window = HlsRetainedWindow(initial.source, maximumSegments: maximumSegments);
    try {
      window.merge(initial);
      renderHlsRetainedManifest(window, localUri: (uri) => uri);
    } on FormatException {
      return false;
    }
    final feed = _Feed(id, fetchSource, window);
    _feeds[id] = feed;
    _rebuild(feed);
    _pump();
    _schedule(feed);
    return true;
  }

  String publish(String id, Uri Function(HlsPrefetchResource resource) localUri) {
    final feed = _feeds[id];
    if (_closed || feed == null || feed.failed) throw StateError('Selected HLS feed is unavailable');
    Uri map(HlsPrefetchResource resource) {
      return localUri(resource);
    }

    final text = renderHlsRetainedManifest(
      feed.window,
      localUri: (uri) => uri,
      segmentUri: (segment) => map(HlsPrefetchResource.media(id, segment)),
      initializationUri: (initialization) => map(HlsPrefetchResource.initialization(initialization)),
      keyUri: (key) => map(HlsPrefetchResource.key(key)),
    );
    feed.published = [feed.window.segments, if (feed.published.isNotEmpty) feed.published.first];
    _prune();
    return text;
  }

  Future<HlsPrefetchLease?> acquire(String key) async {
    final clock = Stopwatch()..start();
    final deadline = pool.bodyIdleTimeout * 4 + const Duration(seconds: 15);
    while (!_closed) {
      _pump();
      final left = deadline - clock.elapsed;
      if (left <= Duration.zero) return null;
      final entry = _items[key];
      try {
        if (entry != null) {
          if (!await entry.$2.ready.timeout(left) || _closed) return null;
          return pool.acquire(key);
        }
        if (_stopped || !requiredKeys.contains(key)) return null;
        await _changed.future.timeout(left);
      } on TimeoutException {
        return null;
      }
    }
    return null;
  }

  /// Local response completion, not a decoder-consumption claim. Keep two
  /// delivered segments and both published generations for repeat requests.
  void delivered(String key) {
    final resource = _items[key]?.$1;
    final feed = _feeds[resource?.feedId];
    if (_closed || _finishing || feed == null || resource?.sequence == null) return;
    final sequence = resource!.sequence!;
    if (sequence <= feed.delivered) return;
    feed.delivered = sequence;
    if (sequence > 1) feed.window.retireBefore(sequence - 1);
    _rebuild(feed);
    _prune();
    _pump();
  }

  void freeze() {
    _finishing = true;
    for (final feed in _feeds.values) {
      feed.timer?.cancel();
      feed.refreshCancellation?.cancel();
    }
  }

  /// End unpublished downloads, retaining complete cached bodies for drain.
  void stopFetching() {
    freeze();
    _stopped = true;
    _notify();
    for (final entry in _items.values.toList()) {
      if (!entry.$2.isReady) _own(pool.evict(entry.$1.key));
    }
  }

  void _schedule(_Feed feed) {
    if (_closed || _finishing || feed.failed || feed.window.ended) return;
    final interval = pollInterval ?? Duration(milliseconds: (feed.window.targetDuration * 500).clamp(500, 30000));
    feed.timer = Timer(interval, () => _own(_refresh(feed)));
  }

  Future<void> _refresh(_Feed feed) async {
    if (_closed || _finishing || feed.failed) return;
    final cancellation = HlsPrefetchCancellation();
    feed.refreshCancellation = cancellation;
    try {
      final snapshot = await fetchSnapshot(feed.source, cancellation);
      if (_closed || _finishing || cancellation.isCancelled) return;
      final evicted = feed.window.merge(snapshot);
      if (evicted.any((s) => s.sequence > feed.delivered)) _markGap();
      _rebuild(feed);
      _prune();
      _pump();
    } on Object {
      // A failed refresh is exposed to the caller, not an endlessly repeated
      // stale manifest. Recording retry/source-refresh policy stays upstream.
      if (!_closed && !_finishing) feed.failed = true;
    } finally {
      feed.refreshCancellation = null;
      _schedule(feed);
    }
  }

  void _rebuild(_Feed feed) {
    final wanted = <String, HlsPrefetchResource>{};
    for (final resource in _dependencies(feed.id, feed.window.segments)) {
      wanted.putIfAbsent(resource.key, () => resource);
    }
    feed.wanted = wanted;
  }

  static Iterable<HlsPrefetchResource> _dependencies(String id, Iterable<HlsSegmentDescriptor> segments) sync* {
    for (final segment in segments) {
      final initialization = segment.initialization;
      if (initialization != null) {
        for (final key in initialization.keys) {
          yield HlsPrefetchResource.key(key);
        }
        yield HlsPrefetchResource.initialization(initialization);
      }
      for (final key in segment.keys) {
        yield HlsPrefetchResource.key(key);
      }
      if (!segment.gap) yield HlsPrefetchResource.media(id, segment);
    }
  }

  void _pump() {
    if (_closed || _stopped || _finishing || _feeds.isEmpty) return;
    final feeds = _feeds.values.where((feed) => !feed.failed).toList();
    if (feeds.isEmpty) return;
    var misses = 0;
    // Reserve space for every supported selected rendition: eager admission
    // of a long first playlist must not prevent the second feed from starting.
    final quota = (pool.maximumEntries ~/ maximumFeeds).clamp(1, 32);
    // Round-robin admission, not one unbounded queue for each rendition.
    while (misses < feeds.length && _items.length < 512) {
      final feed = feeds[_nextFeed++ % feeds.length];
      if (_items.values.where((entry) => entry.$3 == feed.id && entry.$2.failure == null).length >= quota) {
        misses++;
        continue;
      }
      HlsPrefetchResource? next;
      for (final resource in feed.wanted.values) {
        if (!_items.containsKey(resource.key)) {
          next = resource;
          break;
        }
      }
      if (next == null) {
        misses++;
        continue;
      }
      final resource = next;
      HlsPrefetchTicket? ticket;
      try {
        ticket = pool.prefetch(resource.key, (cancel) => loadResource(resource, cancel));
      } on Object {
        feed.failed = true;
        _markGap();
        return;
      }
      if (ticket == null) return; // Bounded backpressure, not an implicit retry.
      final admittedTicket = ticket;
      misses = 0;
      _items[resource.key] = (resource, ticket, feed.id);
      _notify();
      _own(() async {
        final ready = await admittedTicket.ready;
        _notify();
        try {
          onDownloadResult?.call(resource, ready);
        } on Object {
          /* Observation only. */
        }
        if (!ready && !_closed && !_finishing) _markGap();
        if (!ready) {
          await admittedTicket.disposed;
          _notify();
          _pump();
        }
      }());
    }
  }

  void _prune() {
    if (_closed) return;
    final required = requiredKeys;
    for (final key in _items.keys.where((key) => !required.contains(key)).toList()) {
      _items.remove(key);
      _own(() async {
        await pool.evict(key);
        _notify();
        _pump();
      }());
    }
  }

  void _markGap() {
    if (_gap || _closed || _finishing) return;
    _gap = true;
    try {
      onCoverageGap?.call();
    } on Object {
      /* Observation only. */
    }
  }

  void _notify() {
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  void _own(Future<void> job) {
    // Store the handled future so no asynchronous failure is left unobserved.
    late Future<void> owned;
    owned = job
        .catchError((Object _) {
          _markGap();
        })
        .whenComplete(() => _jobs.remove(owned));
    _jobs.add(owned);
  }

  /// Caller ends native/local writers and releases their leases first.
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    stopFetching();
    try {
      await pool.close();
    } finally {
      await Future.wait(_jobs.toList());
      _feeds.clear();
      _items.clear();
    }
  }
}

final class _Feed {
  _Feed(this.id, this.source, this.window);
  final String id;
  final Uri source;
  final HlsRetainedWindow window;
  Map<String, HlsPrefetchResource> wanted = {};
  List<List<HlsSegmentDescriptor>> published = [];
  int delivered = -1;
  bool failed = false;
  Timer? timer;
  HlsPrefetchCancellation? refreshCancellation;
}
