import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show WidthClass;
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/network.dart';
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/danmaku/on_video.dart';
import 'package:pure_live_app/features/danmaku/room_danmaku.dart';
import 'package:pure_live_app/features/multiview/multiview_danmaku.dart';
import 'package:pure_live_app/features/room/playback.dart';
import 'package:pure_live_app/features/room/presentation.dart' show touchPlatform;
import 'package:pure_live_app/features/system/mini_player.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Grid layouts (spec/modules/multiview.md §2).
enum MultiviewLayout {
  one(1, '1×1'),
  two(2, '1×2'),
  four(4, '2×2'),
  onePlusN(4, null),
  nine(9, '3×3');

  new(this.cells, this._grid);

  /// Cells the layout starts with (1+N grows up to the capacity).
  final int cells;
  final String? _grid;

  /// The menu label: the grid, or 1+N's name in the interface language.
  String get label => _grid ?? t.multiview.onePlusN;
}

/// What a cell shows (CEL-1).
enum CellStatus { empty, resolving, playing, offline, error }

/// One cell's state; the session belongs to the cell (CEL-2).
@immutable
final class MultiviewCell {
  const new({
    this.status = CellStatus.empty,
    this.room,
    this.detail,
    this.session,
    this.error,
    this.manualQuality = false,
    this.volume = 1,
    this.paused = false,
  });

  final CellStatus status;
  final RoomRef? room;
  final RoomDetail? detail;
  final PlaybackSession? session;

  /// Why the cell failed, for the message and retry.
  final Object? error;

  /// The user picked a quality; automatic downgrades leave this cell alone (RS-2).
  final bool manualQuality;

  /// The cell's own volume, 0–1, apart from the sound focus and mute-all
  /// (CEL-9); stored per room.
  final double volume;

  /// The user paused this cell (CEL-6): the user's intent, not the engine's
  /// playing flag.
  final bool paused;

  /// Empty, offline and failed cells can take a room (CEL-1).
  bool get assignable => status == CellStatus.empty || status == CellStatus.offline || status == CellStatus.error;

  /// A copy with the user's choices replaced.
  MultiviewCell copyWith({bool? manualQuality, double? volume, bool? paused}) => MultiviewCell(
    status: status,
    room: room,
    detail: detail,
    session: session,
    error: error,
    manualQuality: manualQuality ?? this.manualQuality,
    volume: volume ?? this.volume,
    paused: paused ?? this.paused,
  );
}

/// The whole page state.
@immutable
final class MultiviewState {
  const new({
    required this.layout,
    required this.cells,
    this.audioFocus = 0,
    this.big = 0,
    this.target = 0,
    this.muteAll = false,
    this.danmaku = false,
  });

  final MultiviewLayout layout;
  final List<MultiviewCell> cells;

  /// The only cell allowed to make sound (AUD-1).
  final int audioFocus;

  /// The large cell in 1+N.
  final int big;

  /// Where the next picked room goes (CEL-4).
  final int target;

  /// No cell makes sound, while focus can still move (AUD-3).
  final bool muteAll;

  /// The page's danmaku switch (DM-1): off by default, controls display and
  /// connection.
  final bool danmaku;

  /// The cell page-level controls act on: the big cell in 1+N, else the focus.
  int get selected => layout == MultiviewLayout.onePlusN ? big : audioFocus;

  /// The selected cell, when it exists.
  MultiviewCell? get selectedCell => selected < cells.length ? cells[selected] : null;

  MultiviewState copyWith({
    MultiviewLayout? layout,
    List<MultiviewCell>? cells,
    int? audioFocus,
    int? big,
    int? target,
    bool? muteAll,
    bool? danmaku,
  }) => MultiviewState(
    layout: layout ?? this.layout,
    cells: cells ?? this.cells,
    audioFocus: audioFocus ?? this.audioFocus,
    big: big ?? this.big,
    target: target ?? this.target,
    muteAll: muteAll ?? this.muteAll,
    danmaku: danmaku ?? this.danmaku,
  );
}

/// Decoders a device may run at once (LYT-1): phones and TVs 4, desktops 9.
int multiviewCapacity() => Platform.isAndroid || Platform.isIOS ? 4 : 9;

/// The layouts a window of [width] offers (spec/modules/multiview.md §2,
/// principles §5.2): 1×1, 1×2 and 2×2 everywhere, 1+N from the expanded
/// class, 3×3 from the large class on devices that run 9.
List<MultiviewLayout> multiviewLayoutsFor(WidthClass width, {required int capacity}) => [
  MultiviewLayout.one,
  MultiviewLayout.two,
  MultiviewLayout.four,
  if (width.atLeast(WidthClass.expanded)) MultiviewLayout.onePlusN,
  if (capacity >= 9 && width.atLeast(WidthClass.large)) MultiviewLayout.nine,
];

/// How many rooms [layout] shows at once: 1+N grows to the capacity.
int multiviewHolds(MultiviewLayout layout, {required int capacity}) =>
    layout == MultiviewLayout.onePlusN ? capacity : math.min(layout.cells, capacity);

/// The most rooms one entry can fill with the [layouts] a window offers
/// (ENT-1): more are left out, and the follows page says so.
int multiviewRoomLimit(List<MultiviewLayout> layouts, {required int capacity}) =>
    layouts.map((layout) => multiviewHolds(layout, capacity: capacity)).reduce(math.max);

/// ENT-3: the layout to start with [rooms] rooms: [preferred] (the window's
/// default) when they fit, else the smallest of [layouts] that shows them
/// all (2×2, then 3×3, then 1+N), else the one that shows the most. Rooms
/// must never land in cells a grid does not show.
MultiviewLayout multiviewStartLayout(
  int rooms, {
  required MultiviewLayout preferred,
  required List<MultiviewLayout> layouts,
  required int capacity,
}) {
  if (rooms <= multiviewHolds(preferred, capacity: capacity)) return preferred;
  final larger = [
    for (final layout in [MultiviewLayout.four, MultiviewLayout.nine, MultiviewLayout.onePlusN])
      if (layouts.contains(layout)) layout,
  ];
  for (final layout in larger) {
    if (rooms <= multiviewHolds(layout, capacity: capacity)) return layout;
  }
  return larger.fold(
    preferred,
    (best, layout) =>
        multiviewHolds(layout, capacity: capacity) > multiviewHolds(best, capacity: capacity) ? layout : best,
  );
}

/// Per-room volumes shared with the single room (CEL-9); tests replace it.
abstract interface class RoomVolumes {
  /// The stored volume of [room] (0–1), or null.
  Future<double?> volumeOf(RoomRef room);

  /// Stores the volume of [room].
  Future<void> setVolume(RoomRef room, double volume);
}

final class _StoreRoomVolumes implements RoomVolumes {
  new(this._prefs);

  final RoomPrefStore _prefs;

  @override
  Future<double?> volumeOf(RoomRef room) => _prefs.volumeOf(room);

  @override
  Future<void> setVolume(RoomRef room, double volume) => _prefs.setVolume(room, volume);
}

/// The store's per-room volumes.
final Provider<RoomVolumes> roomVolumesProvider = Provider<RoomVolumes>(
  (ref) => _StoreRoomVolumes(ref.watch(storeProvider).roomPrefs),
);

/// How long the app stays hidden before cells are suspended (RS-3, INT-3).
const Duration multiviewHideDelay = Duration(milliseconds: 1500);

/// Runs the cells: assignment with epochs, sound focus and volume, pauses,
/// layouts, the chat of the selected cell, suspension of cells nobody sees,
/// and release.
class MultiviewController extends Notifier<MultiviewState> {
  /// Global, never reused: late results for a reassigned cell are dropped (INV-MULTI-03).
  int _epoch = 0;

  /// The epoch each cell was last assigned with, by cell index.
  final Map<int, int> _cellEpochs = {};

  /// The latest state, for release on dispose: `state` must not be read
  /// inside a dispose callback.
  MultiviewState? _latest;

  var _silencedRoom = false;

  late MultiviewDanmaku _danmaku;
  ProviderSubscription<AsyncValue<List<BlockRule>>>? _rulesSubscription;
  List<BlockRule> _rules = const [];

  // RS-3: why cells are suspended.
  Timer? _hideTimer;
  var _appHidden = false;
  var _covered = false;

  /// Small cells of 1+N the page reported on screen; null until it reports
  /// after a layout or promotion (REG-MULTI-009).
  Set<int>? _railVisible;
  final Map<PlaybackSession, SuspendToken> _holds = Map.identity();
  final Set<PlaybackSession> _videoOff = Set.identity();

  @override
  MultiviewState build() {
    _danmaku = MultiviewDanmaku(source: () => ref.read(danmakuSourceProvider));
    listenSelf((_, next) {
      _latest = next;
      _syncDanmaku(next);
    });
    ref
      ..listen(danmakuPrefsProvider, (_, prefs) {
        _danmaku.setFilters(filterSettingsFor(prefs, _rules));
        _syncDanmaku(state);
      })
      ..onDispose(() {
        _hideTimer?.cancel();
        _danmaku.dispose();
        _releaseAll();
      });
    return const MultiviewState(
      layout: MultiviewLayout.four,
      cells: [MultiviewCell(), MultiviewCell(), MultiviewCell(), MultiviewCell()],
    );
  }

  /// Starts with [layout] and optionally [rooms] filled in order.
  Future<void> start({required MultiviewLayout layout, List<RoomRef> rooms = const []}) async {
    _silenceSingleRoom();
    setLayout(layout);
    final capacity = multiviewCapacity();
    for (final (index, room) in rooms.take(capacity).indexed) {
      if (index >= state.cells.length) _grow();
      unawaited(assign(index, room));
    }
  }

  /// ENT-2, INV-MULTI-02: the mini window closes (a paused one would stay as
  /// a frozen picture over the grid); otherwise the room page's player
  /// pauses. Once, and never resumed on leaving.
  void _silenceSingleRoom() {
    if (_silencedRoom) return;
    _silencedRoom = true;
    try {
      final mini = ref.read(miniPlayerProvider.notifier);
      if (mini.holding) {
        unawaited(mini.close().catchError((Object _) {}));
      } else if (ref.exists(playbackSessionProvider)) {
        unawaited(ref.read(playbackSessionProvider).pause().catchError((Object _) {}));
      }
    } on Object {
      // A room page going away at this moment has nothing left to silence.
    }
  }

  void _grow() => state = state.copyWith(cells: [...state.cells, const MultiviewCell()]);

  /// Changes the layout without rebuilding playing cells (LYT-3, LYT-4).
  void setLayout(MultiviewLayout layout) {
    final capacity = multiviewCapacity();
    final count = layout == MultiviewLayout.onePlusN
        ? state.cells.length.clamp(2, capacity)
        : layout.cells.clamp(1, capacity);
    final cells = [...state.cells];
    while (cells.length > count) {
      final removed = cells.removeLast();
      _forget(removed.session);
      unawaited(_release(removed));
    }
    while (cells.length < count) {
      cells.add(const MultiviewCell());
    }
    _cellEpochs.removeWhere((index, _) => index >= cells.length);
    int firstPlaying() => cells.indexWhere((c) => c.status == CellStatus.playing).clamp(0, cells.length - 1);
    final focus = state.audioFocus < cells.length ? state.audioFocus : firstPlaying();
    _railVisible = null;
    state = state.copyWith(
      layout: layout,
      cells: cells,
      audioFocus: focus,
      big: layout == MultiviewLayout.onePlusN ? focus : state.big.clamp(0, cells.length - 1),
      target: state.target.clamp(0, cells.length - 1),
    );
    // Holds first: a quality change makes a suspension token stale (INT-2).
    _applyHolds();
    _applySound();
    _applyQualities();
  }

  /// Whether another small cell fits (LYT-1: decoders, not the window).
  bool get canAddCell => state.cells.length < multiviewCapacity();

  /// Adds a small cell in 1+N, up to the capacity.
  void addCell() {
    if (!canAddCell) return;
    _grow();
  }

  /// Picks where the next room goes.
  void setTarget(int index) {
    if (index < state.cells.length) state = state.copyWith(target: index);
  }

  void _setCell(int index, MultiviewCell cell) {
    final cells = [...state.cells];
    cells[index] = cell;
    state = state.copyWith(cells: cells);
  }

  /// Assigns [room] to cell [index] (CEL-3); retry and refresh use it too.
  Future<void> assign(int index, RoomRef room) async {
    if (index >= state.cells.length) return;
    final epoch = ++_epoch;
    _cellEpochs[index] = epoch;
    bool current() => _cellEpochs[index] == epoch;

    final old = state.cells[index];
    _forget(old.session);
    _setCell(index, MultiviewCell(status: CellStatus.resolving, room: room));
    unawaited(_release(old));
    _moveTargetAfter(index);

    final site = ref.read(sitesProvider)[room.platform];
    if (site == null) {
      if (current()) {
        _setCell(index, MultiviewCell(status: CellStatus.error, room: room, error: UnsupportedLink(room.platform)));
      }
      return;
    }
    try {
      final detail = await site.rooms.detail(room);
      if (!current()) return;
      if (detail.state != LiveState.live) {
        // Known offline: no request for streams, no decoder (INV-MULTI-05).
        _setCell(index, MultiviewCell(status: CellStatus.offline, room: room, detail: detail));
        return;
      }
      final volume = await _storedVolume(room);
      if (!current()) return;
      final settings = ref.read(storeProvider).settings;
      final session = newPlaybackSession(ref);
      // Start muted; sound comes with the focus (INV-MULTI-06).
      await session.setVolume(0);
      _setCell(
        index,
        MultiviewCell(status: CellStatus.playing, room: room, detail: detail, session: session, volume: volume),
      );
      await openRoom(
        site: site,
        settings: settings,
        session: session,
        detail: detail,
        preference: _smallCell(index) ? QualityPreference.smooth : null,
        proxiedHosts: ref.read(proxiedHostsProvider),
        cellular: ref.read(networkKindProvider).value == NetworkKind.cellular,
      );
      if (!current()) {
        unawaited(session.dispose());
        return;
      }
      // CEL-6: a pause during the open holds after it.
      if (state.cells[index].paused) unawaited(session.pause());
      // A newly playing cell takes the focus, except small cells in 1+N (AUD-2).
      if (state.layout != MultiviewLayout.onePlusN || index == state.big) {
        setFocus(index);
      } else {
        _applySound();
        _applyHolds();
      }
    } on Object catch (error) {
      if (!current()) return;
      final failed = state.cells[index];
      _forget(failed.session);
      unawaited(failed.session?.dispose());
      _setCell(index, MultiviewCell(status: CellStatus.error, room: room, error: error));
    }
  }

  /// CEL-9: the room's stored volume, else the single room's default.
  Future<double> _storedVolume(RoomRef room) async {
    final settings = ref.read(storeProvider).settings;
    final fallback = settings.get(touchPlatform ? Settings.defaultMobileVolume : Settings.defaultDesktopVolume);
    try {
      return await ref.read(roomVolumesProvider).volumeOf(room) ?? fallback;
    } on Object {
      return fallback;
    }
  }

  /// Assigns the cell's room again, with fresh recovery counts (REC-MV-5).
  Future<void> refresh(int index) async {
    final room = index < state.cells.length ? state.cells[index].room : null;
    if (room != null) await assign(index, room);
  }

  bool _smallCell(int index) => switch (state.layout) {
    MultiviewLayout.onePlusN => index != state.big,
    MultiviewLayout.nine => true,
    _ => false,
  };

  void _moveTargetAfter(int index) {
    final cells = state.cells;
    for (var step = 1; step <= cells.length; step++) {
      final next = (index + step) % cells.length;
      if (cells[next].assignable) {
        state = state.copyWith(target: next);
        return;
      }
    }
  }

  /// Makes [index] the sound focus; in 1+N it also becomes the big cell.
  void setFocus(int index) {
    if (index >= state.cells.length) return;
    final promoted = state.layout == MultiviewLayout.onePlusN && index != state.big;
    // REG-MULTI-009: the small column reports again after a promotion.
    if (promoted) _railVisible = null;
    state = state.copyWith(audioFocus: index, big: state.layout == MultiviewLayout.onePlusN ? index : state.big);
    // Holds first: a quality change makes a suspension token stale (INT-2).
    _applyHolds();
    _applySound();
    _applyQualities();
  }

  /// Mutes every cell or lets the focus speak again (AUD-3).
  void toggleMuteAll() {
    state = state.copyWith(muteAll: !state.muteAll);
    _applySound();
  }

  /// Every other cell muted first, then the focus set to its own volume
  /// (AUD-1, CEL-9).
  void _applySound() {
    final cells = state.cells;
    for (final (index, cell) in cells.indexed) {
      if (index != state.audioFocus) unawaited(cell.session?.setVolume(0));
    }
    if (state.audioFocus < cells.length) {
      final focus = cells[state.audioFocus];
      unawaited(focus.session?.setVolume(state.muteAll ? 0 : focus.volume));
    }
  }

  /// CEL-9: the cell's volume, heard at once when it has the sound; stored
  /// for its room when [persist] (the end of a drag). Mute-all keeps it
  /// silent (AUD-3).
  void setVolume(int index, double value, {bool persist = true}) {
    if (index >= state.cells.length) return;
    final cell = state.cells[index];
    final next = value.clamp(0.0, 1.0);
    if (next != cell.volume) _setCell(index, cell.copyWith(volume: next));
    if (index == state.audioFocus && !state.muteAll) unawaited(cell.session?.setVolume(next));
    final room = cell.room;
    if (persist && room != null) {
      unawaited(ref.read(roomVolumesProvider).setVolume(room, next).catchError((Object _) {}));
    }
  }

  /// CEL-6: pauses or resumes one cell; its status stays "playing".
  void setPaused(int index, {required bool paused}) {
    if (index >= state.cells.length) return;
    final cell = state.cells[index];
    final session = cell.session;
    if (cell.status != CellStatus.playing || session == null || cell.paused == paused) return;
    // A user command makes a suspension token stale (INT-2); holds apply
    // again below.
    _holds.remove(session);
    if (!paused && session.state.phase != PlaybackPhase.idle && session.state.line == null) {
      // Paused before a line was picked: continuing starts over.
      unawaited(refresh(index));
      return;
    }
    _setCell(index, cell.copyWith(paused: paused));
    unawaited(paused ? session.pause() : session.play());
    _applyHolds();
  }

  /// Space: pauses or resumes the selected cell (AUD-5).
  void togglePauseSelected() {
    final cell = state.selectedCell;
    if (cell != null) setPaused(state.selected, paused: !cell.paused);
  }

  /// Small cells use the lowest quality, big ones the preference, unless the
  /// user chose one for that cell (RS-2).
  void _applyQualities() {
    final cellular = ref.read(networkKindProvider).value == NetworkKind.cellular;
    final preference = ref.read(storeProvider).settings.get(cellular ? Settings.qualityMobile : Settings.qualityWifi);
    for (final (index, cell) in state.cells.indexed) {
      final session = cell.session;
      if (session == null || cell.manualQuality) continue;
      final offered = session.state.qualities;
      if (offered.isEmpty) continue;
      final wanted = _smallCell(index) ? offered.last : (preferredQuality(offered, preference) ?? offered.first);
      if (wanted != session.state.quality) unawaited(session.selectQuality(wanted));
    }
  }

  /// A quality the user picked for one cell.
  Future<void> selectQuality(int index, Quality quality) async {
    if (index >= state.cells.length) return;
    final cell = state.cells[index];
    _setCell(index, cell.copyWith(manualQuality: true));
    await cell.session?.selectQuality(quality);
  }

  /// A line the user picked for one cell (CEL-8); the session hands its
  /// lease to the relay (LSE-2).
  Future<void> selectLine(int index, String lineId) async {
    if (index >= state.cells.length) return;
    await state.cells[index].session?.selectLine(lineId);
  }

  /// Empties a cell at once; native release finishes in the background (CEL-7).
  void close(int index) {
    if (index >= state.cells.length) return;
    final cell = state.cells[index];
    _cellEpochs[index] = ++_epoch;
    _forget(cell.session);
    _setCell(index, const MultiviewCell());
    unawaited(_release(cell));
    if (index == state.audioFocus || index == state.big) {
      final playing = state.cells.indexWhere((c) => c.status == CellStatus.playing);
      final next = playing < 0 ? 0 : playing;
      state = state.copyWith(
        audioFocus: index == state.audioFocus ? next : null,
        big: index == state.big ? next : null,
      );
      _applySound();
      _applyHolds();
    }
    state = state.copyWith(target: index);
  }

  // ------------------------------------------------------------- danmaku

  /// DM-1: the page's danmaku switch. Block rules are read from the first
  /// time it is on.
  void setDanmaku({required bool enabled}) {
    if (enabled && _rulesSubscription == null) {
      _rulesSubscription = ref.listen(blockRulesProvider, (_, next) {
        final rules = next.value;
        if (rules == null) return;
        _rules = rules;
        _danmaku.setFilters(filterSettingsFor(ref.read(danmakuPrefsProvider), rules));
      }, fireImmediately: true);
    }
    if (enabled != state.danmaku) state = state.copyWith(danmaku: enabled);
  }

  /// D: flips the danmaku switch (AUD-5).
  void toggleDanmaku() => setDanmaku(enabled: !state.danmaku);

  /// The open chat of the selected cell, if any.
  RoomDanmaku? get danmaku => _danmaku.current;

  /// The page's on-video layer (null detaches it).
  OnVideoDanmaku? get overlay => _danmaku.overlay;

  set overlay(OnVideoDanmaku? value) => _danmaku.overlay = value;

  /// DM-2: the chat follows the selected cell while it plays; the global
  /// "显示弹幕" switch off means no connection (F-DM-01).
  void _syncDanmaku(MultiviewState next) {
    final cell = next.danmaku && ref.read(danmakuPrefsProvider).enabled ? next.selectedCell : null;
    if (cell != null && cell.status == CellStatus.resolving && cell.room == _danmaku.current?.room.ref) {
      // A refresh of the same room keeps its connection.
      _danmaku.hold();
      return;
    }
    final target = cell?.status == CellStatus.playing ? cell : null;
    _danmaku.follow(
      room: target?.detail,
      session: target?.session,
      filters: () => filterSettingsFor(ref.read(danmakuPrefsProvider), _rules),
    );
  }

  // ------------------------------------------------------------- RS-3

  /// The app left or came back to the screen. Cells change only after it
  /// stayed hidden for [multiviewHideDelay] (INT-3); coming back acts at once.
  void setAppHidden({required bool hidden}) {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (hidden) {
      _hideTimer = Timer(multiviewHideDelay, () {
        _hideTimer = null;
        _appHidden = true;
        _applyHolds();
      });
    } else if (_appHidden) {
      _appHidden = false;
      _applyHolds();
    }
  }

  /// An opaque page covers the multiview page: only the sound focus plays on.
  void setCovered({required bool covered}) {
    if (covered == _covered) return;
    _covered = covered;
    _applyHolds();
  }

  /// The small cells of 1+N currently in the viewport (LYT-6, RS-3).
  void setVisibleSmallCells(Iterable<int> visible) {
    final next = visible.toSet();
    if (setEquals(next, _railVisible)) return;
    _railVisible = next;
    _applyHolds();
  }

  /// RS-3: suspends playing cells nobody sees and resumes them by their
  /// token; with background play on, the focus keeps only its sound. The
  /// user's intent never changes here (INV-MULTI-12).
  void _applyHolds() {
    final background = ref.read(storeProvider).settings.get(Settings.backgroundPlay);
    final railVisible = _railVisible;
    for (final (index, cell) in state.cells.indexed) {
      final session = cell.session;
      if (session == null || cell.status != CellStatus.playing) continue;
      final focus = index == state.audioFocus;
      final scrolledOut =
          state.layout == MultiviewLayout.onePlusN &&
          index != state.big &&
          railVisible != null &&
          !railVisible.contains(index);
      final soundOnly = _appHidden && background && focus;
      final hold = scrolledOut || (_covered && !focus) || (_appHidden && !soundOnly);
      final token = _holds[session];
      if (hold) {
        if (session.state.wantsPlay && (token == null || session.state.phase != PlaybackPhase.suspended)) {
          _holds[session] = session.suspend(SuspendReason.background);
        }
      } else if (token != null) {
        _holds.remove(session);
        // A command in between made the token stale while the session
        // still waits for it: a fresh token releases it.
        if (!session.resume(token) && session.state.phase == PlaybackPhase.suspended) {
          session.resume(session.suspend(SuspendReason.background));
        }
      }
      if (soundOnly && !session.state.audioOnly && _videoOff.add(session)) {
        unawaited(session.setAudioOnly(enabled: true).catchError((Object _) {}));
      } else if (!soundOnly && _videoOff.remove(session)) {
        unawaited(session.setAudioOnly(enabled: false).catchError((Object _) {}));
      }
    }
  }

  void _forget(PlaybackSession? session) {
    if (session == null) return;
    _holds.remove(session);
    _videoOff.remove(session);
  }

  // ------------------------------------------------------------- release

  Future<void> _release(MultiviewCell cell) async {
    try {
      await cell.session?.dispose();
    } on Object {
      // A failed release must not affect other cells (EXT-2).
    }
  }

  /// Clears every cell for a safe exit (EXT-2): state first, native release after.
  void _releaseAll() {
    for (final cell in _latest?.cells ?? const <MultiviewCell>[]) {
      unawaited(_release(cell));
    }
  }

  /// Empties all cells synchronously so the videos unmount before the page
  /// pops; the chat disconnects first (EXT-2).
  void clearForExit() {
    _epoch++;
    _hideTimer?.cancel();
    _danmaku.dispose();
    final old = state.cells;
    _holds.clear();
    _videoOff.clear();
    state = state.copyWith(cells: [for (final _ in old) const MultiviewCell()]);
    for (final cell in old) {
      unawaited(_release(cell));
    }
  }
}

/// The multiview page state; disposed with the page.
final NotifierProvider<MultiviewController, MultiviewState> multiviewProvider =
    NotifierProvider.autoDispose<MultiviewController, MultiviewState>(MultiviewController.new);
