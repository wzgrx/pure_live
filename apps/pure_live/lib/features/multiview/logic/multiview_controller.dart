import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/multiview/logic/multiview_session.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/shared/rooms/play_quality.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The arrangements of the multi-view grid (3.x `MultiviewLayout`).
enum MultiviewLayout {
  /// One view.
  single,

  /// Two side by side.
  dual,

  /// Two by two.
  quad,

  /// One large view and a column of small ones (grows on desktop).
  focus;

  /// Cells the layout starts with.
  int get capacity => switch (this) {
    MultiviewLayout.single => 1,
    MultiviewLayout.dual => 2,
    MultiviewLayout.quad || MultiviewLayout.focus => 4,
  };

  /// Columns of the plain grid.
  int get columns => this == MultiviewLayout.single ? 1 : 2;

  /// Rows of the plain grid.
  int get rows => this == MultiviewLayout.quad || this == MultiviewLayout.focus ? 2 : 1;
}

/// Where a cell is (3.x `MultiviewCellStatus`; the playing state itself is
/// the session's [PlaybackState]).
enum CellStage {
  /// No room.
  empty,

  /// Fetching the room, its qualities and its stream.
  resolving,

  /// A stream is open in the cell's session.
  playing,

  /// The platform says the room is not on air.
  offline,

  /// The room or its stream could not be resolved; [MultiviewCell.failure].
  failed,
}

/// The platform of a picked room has no adapter (retired).
final class UnsupportedPlatform implements Exception {
  /// Creates the failure.
  const new(this.platform);

  /// The platform id.
  final String platform;

  @override
  String toString() => 'UnsupportedPlatform($platform)';
}

/// One cell of the grid. The controller changes it; the page reads it.
final class MultiviewCell {
  new _(this.id);

  /// A stable identity of the cell (its video keeps its state when the cell
  /// moves between the large slot and the column).
  final int id;

  LiveRoom? _room;
  CellStage _stage = CellStage.empty;
  Object? _failure;
  LiveSite? _site;
  PlaybackSession? _session;
  List<LivePlayQuality> _qualities = const [];
  int _qualityIndex = 0;
  bool _switching = false;
  double _volume = 1;
  int _epoch = 0;
  LiveQualityDiscoveryScope? _scope;

  /// The room (the fetched detail once known).
  LiveRoom? get room => _room;

  /// Where the cell is.
  CellStage get stage => _stage;

  /// Why [stage] is [CellStage.failed].
  Object? get failure => _failure;

  /// The player; null until the cell first plays.
  PlaybackSession? get session => _session;

  /// The platform's qualities, best first.
  List<LivePlayQuality> get qualities => _qualities;

  /// The quality that plays.
  int get qualityIndex => _qualityIndex;

  /// A quality switch is resolving (the old stream keeps playing).
  bool get switching => _switching;

  /// The room's volume (the one the live room uses too), 0 to 1.
  double get volume => _volume;

  /// Whether picking a room may replace this cell without stopping a
  /// stream (3.x `isMultiviewCellAssignable`).
  bool get assignable => switch (_stage) {
    CellStage.empty || CellStage.offline || CellStage.failed => true,
    CellStage.resolving || CellStage.playing => false,
  };

  /// A stream is open.
  bool get playing => _stage == CellStage.playing;

  /// The session's state, idle when there is none.
  PlaybackState get playback => _session?.state ?? const PlaybackState();

  bool _offscreen = false;

  /// Scrolled out of sight (a small cell of the focus layout): the video is
  /// not decoded (sound only) until it is on screen again.
  bool get offscreen => _offscreen;
}

/// The multi-view logic (3.x `MultiviewController` without GetX): one
/// [PlaybackSession] per cell, one audible cell, the danmaku of the selected
/// cell, per-cell qualities and lines, and the last arrangement.
///
/// Everything it needs is passed in, so tests drive it with fakes.
class MultiviewController extends ChangeNotifier {
  /// Creates the controller; call [start].
  new({
    required this.siteOf,
    required this.newSession,
    required this.danmakuFor,
    required this.danmakuSupports,
    required this.store,
    this.mobile = false,
    int? maxCells,
    this.toast,
    this.danmakuStartTimeout = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : maxCells = maxCells ?? (mobile ? MultiviewLayout.focus.capacity : desktopMaxCells),
       _now = now ?? DateTime.now {
    if (this.maxCells < MultiviewLayout.focus.capacity || this.maxCells > desktopMaxCells) {
      throw ArgumentError.value(this.maxCells, 'maxCells', 'must be between 4 and $desktopMaxCells');
    }
    _filter = DanmakuMessageFilter(clock: _now);
    _cells.addAll([for (var i = 0; i < _layout.capacity; i++) _newCell()]);
  }

  /// Most decoders at once on desktop (3.x); phones stay at four.
  static const int desktopMaxCells = 9;

  /// The meta key of the last arrangement (also in full backups).
  static const String sessionKey = multiviewSessionKey;

  /// The adapter of a platform; null for a retired one.
  final LiveSite? Function(String platform) siteOf;

  /// Makes a player for a cell.
  final PlaybackSession Function() newSession;

  /// A new danmaku connection of a platform.
  final DanmakuConnection Function(String platform) danmakuFor;

  /// Whether a platform has danmaku.
  final bool Function(String platform) danmakuSupports;

  /// Settings, follows, block lists and the last arrangement.
  final LiveStore store;

  /// A phone (four cells at most; the default volume of phones).
  final bool mobile;

  /// Most cells the focus layout may grow to.
  final int maxCells;

  /// Shows a short message.
  final void Function(String message)? toast;

  /// How long the first danmaku attempt may take (as the live room).
  final Duration danmakuStartTimeout;

  final DateTime Function() _now;
  late DanmakuMessageFilter _filter;
  final List<MultiviewCell> _cells = [];
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final StreamController<LiveMessage> _flying = StreamController.broadcast(sync: true);
  final StreamController<LiveRetraction> _retractions = StreamController.broadcast(sync: true);
  int _nextCellId = 0;
  MultiviewLayout _layout = MultiviewLayout.quad;
  int _focused = 0;
  int _audio = 0;
  bool _allMuted = false;
  bool _smallCellsLowQuality = false;
  bool _danmakuEnabled = false;
  bool _disposed = false;
  bool _restoring = false;
  List<LiveRoom?> _savedRooms = const [];
  DanmakuConnection? _danmaku;
  StreamSubscription<DanmakuEvent>? _danmakuEvents;
  String? _danmakuKey;
  int _danmakuEpoch = 0;

  MultiviewCell _newCell() => MultiviewCell._(_nextCellId++);

  /// The cells, in grid order.
  List<MultiviewCell> get cells => List.unmodifiable(_cells);

  /// The arrangement.
  MultiviewLayout get layout => _layout;

  /// The large cell of the focus layout.
  int get focusedIndex => _focused;

  /// The cell whose sound plays (3.x's audio focus).
  int get audioIndex => _audio;

  /// The cell the page-level controls act on: the large cell in the focus
  /// layout, else the audible one (3.x `_selectedCellIndex`).
  int get selectedIndex =>
      _cells.isEmpty ? 0 : (_layout == MultiviewLayout.focus ? _focused : _audio).clamp(0, _cells.length - 1);

  /// Every cell is silent.
  bool get allMuted => _allMuted;

  /// Small cells of the focus layout play the lowest quality.
  bool get smallCellsLowQuality => _smallCellsLowQuality;

  /// Danmaku fly over the selected cell.
  bool get danmakuEnabled => _danmakuEnabled;

  /// Whether the focus layout may get another small cell.
  bool get canAddCell => _layout == MultiviewLayout.focus && _cells.length < maxCells;

  /// Rooms of the last visit that can be brought back (none once a cell
  /// was filled in this visit).
  List<LiveRoom?> get savedRooms => _savedRooms;

  /// Chat messages for the flying layer, as they pass the filters.
  Stream<LiveMessage> get flying => _flying.stream;

  /// Messages the platform took back.
  Stream<LiveRetraction> get retractions => _retractions.stream;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(MultiviewCell cell, int epoch) => !_disposed && cell._epoch == epoch && _cells.contains(cell);

  /// Reads the last arrangement and follows the danmaku filters.
  Future<void> start() async {
    _subscriptions
      ..add(store.blockLists.watch(BlockKind.keyword).listen((_) => unawaited(_reloadFilter())))
      ..add(store.blockLists.watch(BlockKind.user).listen((_) => unawaited(_reloadFilter())));
    for (final setting in _filterSettings) {
      _subscriptions.add(store.settings.watch(setting).skip(1).listen((_) => unawaited(_reloadFilter())));
    }
    await _reloadFilter();
    await _load();
  }

  static const List<Setting<Object>> _filterSettings = [
    Settings.collapseRepeatedDanmaku,
    Settings.repeatedDanmakuWindowSeconds,
    Settings.enableDanmakuSimilarityFilter,
    Settings.danmakuSimilarityThreshold,
    Settings.danmakuSimilarityCacheDuration,
    Settings.danmakuSimilarityMaxCacheSize,
  ];

  Future<void> _reloadFilter() async {
    final settings = store.settings;
    final keywords = await store.blockLists.list(BlockKind.keyword);
    final users = await store.blockLists.list(BlockKind.user);
    if (_disposed) return;
    _filter.settings = DanmakuFilterSettings(
      collapseRepeated: settings.get(Settings.collapseRepeatedDanmaku),
      repeatedWindowSeconds: settings.get(Settings.repeatedDanmakuWindowSeconds),
      similarityEnabled: settings.get(Settings.enableDanmakuSimilarityFilter),
      similarityThreshold: settings.get(Settings.danmakuSimilarityThreshold),
      similarityCacheSeconds: settings.get(Settings.danmakuSimilarityCacheDuration),
      similarityMaxCacheSize: settings.get(Settings.danmakuSimilarityMaxCacheSize),
      blockedUsers: users,
      blockedKeywords: keywords,
    );
  }

  // ---- the last arrangement ----

  Future<void> _load() async {
    try {
      final raw = await store.meta.get(sessionKey);
      if (raw == null || _disposed) return;
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return;
      _smallCellsLowQuality = json['smallCellsLowQuality'] == true;
      _danmakuEnabled = json['danmaku'] == true;
      final layout = MultiviewLayout.values.asNameMap()[json['layout']];
      if (layout != null && layout != _layout && _cells.every((cell) => cell.stage == CellStage.empty)) {
        await setLayout(layout, save: false);
      }
      final rooms = json['rooms'];
      if (rooms is List<Object?> && _cells.every((cell) => cell.stage == CellStage.empty)) {
        _savedRooms = [
          for (final item in rooms.take(maxCells))
            if (item is Map<String, Object?>) _roomOrNull(item) else null,
        ];
        if (_savedRooms.every((room) => room == null)) _savedRooms = const [];
      }
      _notify();
    } on Object catch (error, stackTrace) {
      developer.log('Reading the last multi-view failed', name: 'Multiview', error: error, stackTrace: stackTrace);
    }
  }

  static LiveRoom? _roomOrNull(Map<String, Object?> json) {
    try {
      final room = LiveRoom.fromJson(json);
      return room.platform.trim().isEmpty || room.roomId.trim().isEmpty ? null : room;
    } on Object {
      return null;
    }
  }

  Future<void> _save() async {
    if (_disposed || _restoring) return;
    final json = {
      'layout': _layout.name,
      'smallCellsLowQuality': _smallCellsLowQuality,
      'danmaku': _danmakuEnabled,
      'rooms': [
        for (final cell in _cells)
          if (cell.room case final room? when cell.stage != CellStage.empty) _cardFields(room) else null,
      ],
    };
    try {
      await store.meta.set(sessionKey, jsonEncode(json));
    } on Object catch (error, stackTrace) {
      developer.log('Saving the multi-view failed', name: 'Multiview', error: error, stackTrace: stackTrace);
    }
  }

  /// What a restore needs (the danmaku and play data are fetched again).
  static Map<String, Object?> _cardFields(LiveRoom room) => LiveRoom(
    platform: room.platform,
    roomId: room.roomId,
    nick: room.nick,
    title: room.title,
    avatar: room.avatar,
    cover: room.cover,
  ).toJson();

  /// Opens the rooms of the last visit in their cells.
  Future<void> restoreLast() async {
    final rooms = _savedRooms;
    if (rooms.isEmpty || _disposed) return;
    _savedRooms = const [];
    _restoring = true;
    try {
      if (rooms.length > _cells.length) {
        if (_layout != MultiviewLayout.focus) await setLayout(MultiviewLayout.focus, save: false);
        while (_cells.length < rooms.length && canAddCell) {
          addCell();
        }
      }
      final pending = <Future<void>>[
        for (var i = 0; i < rooms.length && i < _cells.length; i++)
          if (rooms[i] case final room?) assign(i, room),
      ];
      _notify();
      await Future.wait(pending);
    } finally {
      _restoring = false;
    }
    await _save();
  }

  /// Forgets the last visit's rooms (the user starts afresh).
  void dismissSaved() {
    _savedRooms = const [];
    _notify();
  }

  // ---- layout ----

  /// Changes the arrangement (3.x `setLayout`): cells beyond the new size are
  /// released; the first ones keep playing.
  Future<void> setLayout(MultiviewLayout next, {bool save = true}) async {
    if (next == _layout || _disposed) return;
    final capacity = next.capacity;
    final removed = _cells.length > capacity ? _cells.sublist(capacity) : const <MultiviewCell>[];
    if (removed.isNotEmpty) _cells.removeRange(capacity, _cells.length);
    while (_cells.length < capacity) {
      _cells.add(_newCell());
    }
    _layout = next;
    // The large view follows the sound, so no small cell plays aloud.
    if (next == MultiviewLayout.focus) _focused = _audio.clamp(0, capacity - 1);
    if (_focused >= capacity) _focused = capacity - 1;
    if (_audio >= capacity) _refocus(fallback: 0);
    _notify();
    unawaited(_syncDanmaku());
    if (save) unawaited(_save());
    await Future.wait(removed.map(_release));
  }

  /// Adds an empty small cell to the focus layout.
  void addCell() {
    if (!canAddCell) return;
    _cells.add(_newCell());
    _notify();
  }

  /// Shows cell [index] large in the focus layout; its sound plays. With
  /// [smallCellsLowQuality] the new large cell gets the normal quality and
  /// the previous one the lowest (3.x `promoteCell`).
  Future<void> promote(int index) async {
    if (index < 0 || index >= _cells.length) return;
    final previous = _focused;
    _focused = index;
    await setAudioFocus(index);
    if (!_smallCellsLowQuality || _layout != MultiviewLayout.focus) return;
    final promoted = _cells[index];
    final normal = _normalQuality(promoted);
    if (promoted.playing && promoted.qualityIndex != normal) await _switchQuality(promoted, normal, manual: false);
    if (previous == index || previous >= _cells.length) return;
    final demoted = _cells[previous];
    if (demoted.playing && demoted.qualityIndex != demoted.qualities.length - 1) {
      await _switchQuality(demoted, demoted.qualities.length - 1, manual: false);
    }
  }

  // ---- rooms ----

  /// The cell that already shows [room], or -1.
  int indexOfRoom(LiveRoom room) =>
      _cells.indexWhere((cell) => cell.stage != CellStage.empty && (cell.room?.hasSameIdentity(room) ?? false));

  /// Plays [picked] in cell [index] (3.x `assignRoom`): the detail is always
  /// fetched (a stored offline state may be old), then the qualities and the
  /// stream. The cell's sound plays unless it is a small cell of the focus
  /// layout.
  Future<void> assign(int index, LiveRoom picked) async {
    if (_disposed || index < 0 || index >= _cells.length) return;
    final cell = _cells[index];
    final epoch = ++cell._epoch;
    cell._scope?.cancel();
    cell._scope = null;
    if (!_restoring) _savedRooms = const [];
    final site = siteOf(picked.platform);
    cell
      .._room = picked
      .._site = site
      .._failure = null
      .._qualities = const []
      .._qualityIndex = 0
      .._switching = false
      .._volume = _roomVolume(picked)
      .._stage = site == null ? CellStage.failed : CellStage.resolving;
    if (site == null) cell._failure = UnsupportedPlatform(picked.platform);
    _notify();
    final previous = cell._session;
    if (previous != null && previous.state.status != PlaybackStatus.idle) await previous.stop();
    if (site == null || !_current(cell, epoch)) return;

    final LiveRoom detail;
    try {
      detail = switch (site) {
        final LiveSiteRecordRoomResolver strict => await strict.getRoomDetailForRecording(roomId: picked.roomId),
        _ => await site.getRoomDetail(roomId: picked.roomId),
      };
    } on Object catch (error, stackTrace) {
      if (!_current(cell, epoch)) return;
      developer.log('Room detail failed', name: 'Multiview', error: error, stackTrace: stackTrace);
      cell._room = picked.pendingAfterError();
      _fail(cell, error);
      return;
    }
    if (!_current(cell, epoch)) return;
    final room = cell._room = detail.withAudienceFallbackFrom(picked).fillFromDetail(picked);
    unawaited(_guard(() => store.follows.update([room]), 'follow snapshot'));
    if (!room.isPlayableNow) {
      cell._stage = CellStage.offline;
      _notify();
      unawaited(_syncDanmaku());
      unawaited(_save());
      return;
    }

    final scope = cell._scope = LiveQualityDiscoveryScope();
    final List<LivePlayQuality> found;
    try {
      found = _normalizeQualities(await scope.discover(site, room));
    } on Object catch (error) {
      if (!_current(cell, epoch)) return;
      _fail(cell, error);
      return;
    } finally {
      if (identical(cell._scope, scope)) cell._scope = null;
      unawaited(scope.close());
    }
    if (!_current(cell, epoch)) return;
    if (found.isEmpty) {
      _fail(cell, StreamUnavailable(site.id, 'no qualities'));
      return;
    }
    cell._qualities = found;
    final small = _layout == MultiviewLayout.focus && _cells.indexOf(cell) != _focused;
    final quality = _smallCellsLowQuality && small ? found.length - 1 : _normalQuality(cell);
    final opened = await _openQuality(cell, quality, epoch, manual: false);
    if (!opened || !_current(cell, epoch)) return;
    final position = _cells.indexOf(cell);
    // A small cell of the focus layout starts silent (3.x); elsewhere the
    // new cell becomes the sound.
    if (_layout != MultiviewLayout.focus || position == _focused) {
      await setAudioFocus(position);
    } else {
      _applyVolumes();
    }
    unawaited(_syncDanmaku());
    unawaited(_save());
  }

  int _normalQuality(MultiviewCell cell) =>
      defaultQualityIndex(cell.qualities, store.settings.get(Settings.preferResolution));

  void _fail(MultiviewCell cell, Object error) {
    cell
      .._stage = CellStage.failed
      .._failure = error
      .._qualities = const []
      .._switching = false;
    final session = cell._session;
    if (session != null && session.state.status != PlaybackStatus.idle) unawaited(session.stop());
    _notify();
    unawaited(_syncDanmaku());
  }

  /// Resolves quality [index] of [cell] and opens it in the cell's session.
  Future<bool> _openQuality(MultiviewCell cell, int index, int epoch, {required bool manual}) async {
    final site = cell._site;
    final room = cell._room;
    if (site == null || room == null) return false;
    final requested = cell._qualities[index];
    final LivePlayUrlResolution resolution;
    try {
      resolution = manual
          ? await site.resolvePlayUrlsForRecovery(detail: room, quality: requested)
          : await site.resolvePlayUrls(detail: room, quality: requested);
    } on Object catch (error) {
      if (!_current(cell, epoch)) return false;
      if (cell.playing) {
        // A failed switch keeps the stream that plays.
        if (manual) toast?.call(failureText(error));
        return false;
      }
      _fail(cell, error);
      return false;
    }
    if (!_current(cell, epoch)) return false;
    if (!resolution.hasSources) {
      if (cell.playing) {
        if (manual) toast?.call(i18n('cannot_read_play_url'));
        return false;
      }
      _fail(cell, StreamUnavailable(site.id, 'no urls'));
      return false;
    }
    // A LAN source (a home IPTV server) needs Android 17's local-network
    // permission first; refused, the user is told and the open fails as usual.
    await ensureLocalNetworkFor(resolution.lines.map((line) => line.url), toast: toast);
    if (!_current(cell, epoch)) return false;
    final applied = resolveAppliedPlayQuality(qualities: cell._qualities, requested: requested, resolution: resolution);
    final appliedIndex = cell._qualities.indexWhere((q) => q.selectionId == applied.selectionId);
    final playing = appliedIndex >= 0 ? appliedIndex : index;
    if (manual && playing != index) {
      toast?.call(i18n('quality_limited_to', args: {'quality': cell._qualities[playing].quality}));
    }
    cell
      .._qualities = List.unmodifiable(List.of(cell._qualities)..[playing] = applied)
      .._qualityIndex = playing
      .._stage = CellStage.playing
      .._failure = null;
    final session = cell._session ??= newSession();
    _notify();
    final quality = cell._qualities[playing];
    session.setPresentationVisible(visible: !cell._offscreen);
    await session.open(
      PlaybackRequest(
        site: site.id,
        plan: _plan(room, resolution),
        refresh: () async => _plan(room, await site.resolvePlayUrlsForRecovery(detail: room, quality: quality)),
        audioOnly: cell._offscreen,
        volume: _audibleVolume(cell),
      ),
    );
    return _current(cell, epoch);
  }

  /// The cells whose video is out of sight ([MultiviewCell.offscreen], by
  /// [MultiviewCell.id]); the others are on screen. A cell out of sight
  /// stops decoding its video and its stalled-picture watchdog (UI_PLAN
  /// §9.3, 3.x `focus_rail_visibility.dart`); its sound, if any, goes on.
  void setOffscreen(Set<int> ids) {
    for (final cell in _cells) {
      final offscreen = ids.contains(cell.id);
      if (offscreen == cell._offscreen) continue;
      cell._offscreen = offscreen;
      final session = cell._session;
      if (session == null) continue;
      session.setPresentationVisible(visible: !offscreen);
      if (cell.playing) unawaited(_guard(() => session.setAudioOnly(enabled: offscreen), 'video output'));
    }
  }

  PlaybackPlan _plan(LiveRoom room, LivePlayUrlResolution resolution) =>
      PlaybackPlan.of(resolution, preferH264: store.settings.get(Settings.preferH264), onDemand: room.isRecord);

  /// Plays quality [qualityIndex] in cell [index]; the old stream plays
  /// until the new one resolves.
  Future<void> selectQuality(int index, int qualityIndex) async {
    if (index < 0 || index >= _cells.length) return;
    await _switchQuality(_cells[index], qualityIndex, manual: true);
  }

  Future<void> _switchQuality(MultiviewCell cell, int qualityIndex, {required bool manual}) async {
    if (!cell.playing || cell._switching) return;
    if (qualityIndex < 0 || qualityIndex >= cell._qualities.length || qualityIndex == cell._qualityIndex) return;
    cell._switching = true;
    _notify();
    try {
      await _openQuality(cell, qualityIndex, cell._epoch, manual: manual);
    } finally {
      cell._switching = false;
      _notify();
    }
  }

  /// Plays line [line] of cell [index].
  Future<void> selectLine(int index, int line) async {
    if (index < 0 || index >= _cells.length) return;
    final session = _cells[index]._session;
    if (session == null || !_cells[index].playing) return;
    await session.selectLine(line);
  }

  /// Pauses or resumes cell [index].
  Future<void> togglePlay(int index) async {
    if (index < 0 || index >= _cells.length) return;
    final session = _cells[index]._session;
    if (session == null || !_cells[index].playing) return;
    await session.togglePlayPause();
  }

  /// Plays cell [index] again: the stream when only playback failed, else
  /// the whole room (the retry and refresh buttons).
  Future<void> retry(int index, {bool reload = false}) async {
    if (index < 0 || index >= _cells.length) return;
    final cell = _cells[index];
    final room = cell.room;
    if (room == null) return;
    final session = cell._session;
    if (!reload &&
        cell.playing &&
        session != null &&
        session.state.status == PlaybackStatus.error &&
        session.state.failure != SourceFailureKind.terminal) {
      await session.retry();
      return;
    }
    await assign(index, room);
  }

  /// Pauses every cell that plays (the live room opens on top); returns the
  /// cells to resume with [resumeCells].
  Future<Set<int>> pauseAll() async {
    final paused = <int>{};
    for (final cell in _cells) {
      final session = cell._session;
      if (session == null || !cell.playing || !session.state.isActive) continue;
      paused.add(cell.id);
      await session.pause();
    }
    return paused;
  }

  /// Resumes the cells [pauseAll] paused that still show the same stream.
  Future<void> resumeCells(Set<int> ids) async {
    for (final cell in _cells) {
      final session = cell._session;
      if (session == null || !cell.playing || !ids.contains(cell.id)) continue;
      if (session.state.status == PlaybackStatus.paused) await session.resume();
    }
  }

  /// Empties cell [index] and releases its player (3.x `removeCell`).
  Future<void> remove(int index) async {
    if (index < 0 || index >= _cells.length) return;
    final cell = _cells[index];
    final session = _clear(cell);
    if (_audio == index) _refocus(fallback: index);
    if (_focused == index) _focused = _firstPlaying() ?? 0;
    _notify();
    unawaited(_syncDanmaku());
    unawaited(_save());
    if (session != null) await session.dispose();
  }

  PlaybackSession? _clear(MultiviewCell cell) {
    cell._epoch++;
    cell._scope?.cancel();
    cell._scope = null;
    final session = cell._session;
    cell
      .._session = null
      .._room = null
      .._site = null
      .._stage = CellStage.empty
      .._failure = null
      .._qualities = const []
      .._qualityIndex = 0
      .._switching = false;
    return session;
  }

  Future<void> _release(MultiviewCell cell) async {
    final session = _clear(cell);
    if (session != null) await session.dispose();
  }

  int? _firstPlaying() {
    final index = _cells.indexWhere((cell) => cell.playing);
    return index < 0 ? null : index;
  }

  void _refocus({required int fallback}) {
    final target = _firstPlaying();
    if (target != null) {
      unawaited(setAudioFocus(target));
    } else {
      _audio = fallback.clamp(0, math.max(0, _cells.length - 1));
    }
  }

  // ---- sound ----

  double _roomVolume(LiveRoom room) {
    final settings = store.settings;
    final saved = <String, double>{
      for (final MapEntry(:key, :value) in settings.get(Settings.roomVolumes).entries)
        if (value is num) key: value.toDouble(),
    };
    return roomVolume(
      platform: room.platform,
      roomId: room.roomId,
      saved: saved,
      globalMute: settings.get(Settings.globalVolumeMute),
      mobile: mobile,
      defaultMobile: settings.get(Settings.defaultMobileVolume),
      defaultDesktop: settings.get(Settings.defaultDesktopVolume),
    );
  }

  double _audibleVolume(MultiviewCell cell) => !_allMuted && _cells.indexOf(cell) == _audio ? cell._volume : 0;

  void _applyVolumes() {
    for (final cell in _cells) {
      final session = cell._session;
      if (session != null && cell.playing) unawaited(session.setVolume(_audibleVolume(cell)));
    }
  }

  /// Only cell [index] plays aloud (3.x `setAudioFocus`).
  Future<void> setAudioFocus(int index) async {
    if (index < 0 || index >= _cells.length) return;
    _audio = index;
    _applyVolumes();
    _notify();
    unawaited(_syncDanmaku());
  }

  /// Silences every cell, or brings the audible cell back.
  void toggleMuteAll() {
    _allMuted = !_allMuted;
    _applyVolumes();
    _notify();
  }

  /// Sets the volume of cell [index]; [save] keeps it for the room (the
  /// live room opens with it too). While a slider moves ([save] false) the
  /// page is not told: the slider shows its own value, so the cells and the
  /// picker do not rebuild on every step (docs/T12/T12a/T12a.2 性能要点).
  Future<void> setVolume(int index, double volume, {bool save = false}) async {
    if (index < 0 || index >= _cells.length) return;
    final cell = _cells[index].._volume = volume.isFinite ? volume.clamp(0, 1).toDouble() : 1;
    final session = cell._session;
    if (session != null && cell.playing) await session.setVolume(_audibleVolume(cell));
    if (!save) return;
    _notify();
    final room = cell.room;
    if (room == null) return;
    await _guard(() async {
      final saved = Map<String, Object?>.of(store.settings.get(Settings.roomVolumes));
      saved[roomVolumeKey(room.platform, room.roomId)] = cell._volume;
      await store.settings.set(Settings.roomVolumes, saved);
    }, 'room volume');
  }

  // ---- quality saver ----

  /// Turns the small-cell saver on or off (focus layout); playing small
  /// cells switch at once (3.x `_reconcileSmallCellQualities`).
  Future<void> setSmallCellsLowQuality({required bool enabled}) async {
    if (enabled == _smallCellsLowQuality) return;
    _smallCellsLowQuality = enabled;
    _notify();
    unawaited(_save());
    if (_layout != MultiviewLayout.focus) return;
    for (var i = 0; i < _cells.length; i++) {
      final cell = _cells[i];
      if (i == _focused || !cell.playing || cell.qualities.isEmpty) continue;
      final target = enabled ? cell.qualities.length - 1 : _normalQuality(cell);
      if (cell.qualityIndex != target) await _switchQuality(cell, target, manual: false);
    }
  }

  // ---- danmaku ----

  /// Shows or hides the danmaku of the selected cell.
  void setDanmakuEnabled({required bool enabled}) {
    if (enabled == _danmakuEnabled) return;
    _danmakuEnabled = enabled;
    _notify();
    unawaited(_save());
    if (enabled) {
      final room = _cells.isEmpty ? null : _cells[selectedIndex].room;
      if (room != null && !danmakuSupports(room.platform)) toast?.call(i18n('live_play_danmaku_unsupported'));
    }
    unawaited(_syncDanmaku());
  }

  LiveRoom? _danmakuTarget() {
    if (!_danmakuEnabled || _disposed || _cells.isEmpty) return null;
    final cell = _cells[selectedIndex];
    final room = cell.room;
    if (!cell.playing || room == null || room.danmakuData == null) return null;
    if (!danmakuSupports(room.platform) || room.platform == SiteIds.iptv) return null;
    return room;
  }

  /// Connects the danmaku of the selected cell, or closes it (3.x
  /// `_syncDanmakuSession`; idempotent).
  Future<void> _syncDanmaku() async {
    final target = _danmakuTarget();
    final key = target?.identityKey;
    if (key != null && key == _danmakuKey && _danmaku?.status != DanmakuStatus.closed) return;
    final old = _danmaku;
    final oldEvents = _danmakuEvents;
    _danmaku = null;
    _danmakuEvents = null;
    _danmakuKey = null;
    final epoch = ++_danmakuEpoch;
    if (old != null) {
      unawaited(oldEvents?.cancel());
      unawaited(_guard(old.close, 'danmaku close'));
    }
    if (target == null) return;
    final connection = _danmaku = danmakuFor(target.platform);
    _danmakuKey = key;
    _filter = DanmakuMessageFilter(settings: _filter.settings, clock: _now);
    _danmakuEvents = connection.events.listen((event) {
      if (epoch == _danmakuEpoch && !_disposed) _onDanmaku(event);
    });
    try {
      await connection.connect(target.danmakuData).timeout(danmakuStartTimeout);
    } on Object catch (error, stackTrace) {
      if (epoch != _danmakuEpoch) return;
      developer.log('Danmaku start failed', name: 'Multiview', error: error, stackTrace: stackTrace);
      _danmakuKey = null;
      await _guard(connection.close, 'danmaku close');
    }
  }

  void _onDanmaku(DanmakuEvent event) {
    if (event is! DanmakuReceived) return;
    final message = event.message;
    switch (message.type) {
      case LiveMessageType.chat:
        if (_filter.accepts(message)) _flying.add(message);
      case LiveMessageType.retraction:
        if (message.data case final LiveRetraction retraction) _retractions.add(retraction);
      case LiveMessageType.online || LiveMessageType.superChat || LiveMessageType.notice || LiveMessageType.gift:
        return;
    }
  }

  Future<void> _guard(Future<void> Function() action, String what) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      developer.log('$what failed', name: 'Multiview', error: error, stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _danmakuEpoch++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_danmakuEvents?.cancel());
    final danmaku = _danmaku;
    if (danmaku != null) unawaited(_guard(danmaku.close, 'danmaku close'));
    for (final cell in _cells) {
      final session = _clear(cell);
      if (session != null) unawaited(session.dispose());
    }
    unawaited(_flying.close());
    unawaited(_retractions.close());
    super.dispose();
  }
}

/// [qualities] without blank labels and repeated options (3.x
/// `normalizePlayQualities`).
List<LivePlayQuality> _normalizeQualities(List<LivePlayQuality> qualities) {
  final seen = <String>{};
  return [
    for (final quality in qualities)
      if (quality.quality.trim().isNotEmpty && seen.add('${quality.selectionId}')) quality,
  ];
}
