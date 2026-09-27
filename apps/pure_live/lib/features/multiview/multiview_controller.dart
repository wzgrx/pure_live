import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/network.dart';
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/room/playback.dart';

/// Grid layouts (spec/modules/multiview.md §2).
enum MultiviewLayout {
  one(1, '1×1'),
  two(2, '1×2'),
  four(4, '2×2'),
  onePlusN(4, '一大多小'),
  nine(9, '3×3');

  new(this.cells, this.label);

  /// Cells the layout starts with (1+N grows up to the capacity).
  final int cells;
  final String label;
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
  });

  final CellStatus status;
  final RoomRef? room;
  final RoomDetail? detail;
  final PlaybackSession? session;

  /// Why the cell failed, for the message and retry.
  final Object? error;

  /// The user picked a quality; automatic downgrades leave this cell alone (RS-2).
  final bool manualQuality;

  /// Empty, offline and failed cells can take a room (CEL-1).
  bool get assignable => status == CellStatus.empty || status == CellStatus.offline || status == CellStatus.error;
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

  /// The cell page-level controls act on: the big cell in 1+N, else the focus.
  int get selected => layout == MultiviewLayout.onePlusN ? big : audioFocus;

  MultiviewState copyWith({
    MultiviewLayout? layout,
    List<MultiviewCell>? cells,
    int? audioFocus,
    int? big,
    int? target,
    bool? muteAll,
  }) => MultiviewState(
    layout: layout ?? this.layout,
    cells: cells ?? this.cells,
    audioFocus: audioFocus ?? this.audioFocus,
    big: big ?? this.big,
    target: target ?? this.target,
    muteAll: muteAll ?? this.muteAll,
  );
}

/// Decoders a device may run at once (LYT-1): phones and TVs 4, desktops 9.
int multiviewCapacity() => Platform.isAndroid || Platform.isIOS ? 4 : 9;

/// Runs the cells: assignment with epochs, sound focus, layouts, release.
class MultiviewController extends Notifier<MultiviewState> {
  /// Global, never reused: late results for a reassigned cell are dropped (INV-MULTI-03).
  int _epoch = 0;

  /// The epoch each cell was last assigned with, by cell index.
  final Map<int, int> _cellEpochs = {};

  /// The latest state, for release on dispose: `state` must not be read
  /// inside a dispose callback.
  MultiviewState? _latest;

  @override
  MultiviewState build() {
    listenSelf((_, next) => _latest = next);
    ref.onDispose(_releaseAll);
    return const MultiviewState(
      layout: MultiviewLayout.four,
      cells: [MultiviewCell(), MultiviewCell(), MultiviewCell(), MultiviewCell()],
    );
  }

  /// Starts with [layout] and optionally [rooms] filled in order.
  Future<void> start({required MultiviewLayout layout, List<RoomRef> rooms = const []}) async {
    setLayout(layout);
    final capacity = multiviewCapacity();
    for (final (index, room) in rooms.take(capacity).indexed) {
      if (index >= state.cells.length) _grow();
      unawaited(assign(index, room));
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
      unawaited(_release(cells.removeLast()));
    }
    while (cells.length < count) {
      cells.add(const MultiviewCell());
    }
    _cellEpochs.removeWhere((index, _) => index >= cells.length);
    int firstPlaying() => cells.indexWhere((c) => c.status == CellStatus.playing).clamp(0, cells.length - 1);
    final focus = state.audioFocus < cells.length ? state.audioFocus : firstPlaying();
    state = state.copyWith(
      layout: layout,
      cells: cells,
      audioFocus: focus,
      big: layout == MultiviewLayout.onePlusN ? focus : state.big.clamp(0, cells.length - 1),
      target: state.target.clamp(0, cells.length - 1),
    );
    _applySound();
    _applyQualities();
  }

  /// Adds a small cell in 1+N, up to the capacity.
  void addCell() {
    if (state.cells.length >= multiviewCapacity()) return;
    _grow();
  }

  /// Picks where the next room goes.
  void setTarget(int index) => state = state.copyWith(target: index);

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
      final settings = ref.read(storeProvider).settings;
      final session = newPlaybackSession(ref);
      // Start muted; sound comes with the focus (INV-MULTI-06).
      await session.setVolume(0);
      _setCell(index, MultiviewCell(status: CellStatus.playing, room: room, detail: detail, session: session));
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
      // A newly playing cell takes the focus, except small cells in 1+N (AUD-2).
      if (state.layout != MultiviewLayout.onePlusN || index == state.big) {
        setFocus(index);
      } else {
        _applySound();
      }
    } on Object catch (error) {
      if (!current()) return;
      final failed = state.cells[index];
      unawaited(failed.session?.dispose());
      _setCell(index, MultiviewCell(status: CellStatus.error, room: room, error: error));
    }
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
    state = state.copyWith(audioFocus: index, big: state.layout == MultiviewLayout.onePlusN ? index : state.big);
    _applySound();
    _applyQualities();
  }

  /// Mutes every cell or lets the focus speak again (AUD-3).
  void toggleMuteAll() {
    state = state.copyWith(muteAll: !state.muteAll);
    _applySound();
  }

  /// Every other cell muted first, then the focus set (AUD-1).
  void _applySound() {
    final cells = state.cells;
    for (final (index, cell) in cells.indexed) {
      if (index != state.audioFocus) unawaited(cell.session?.setVolume(0));
    }
    if (state.audioFocus < cells.length) {
      unawaited(cells[state.audioFocus].session?.setVolume(state.muteAll ? 0 : 1));
    }
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
    final cell = state.cells[index];
    _setCell(
      index,
      MultiviewCell(
        status: cell.status,
        room: cell.room,
        detail: cell.detail,
        session: cell.session,
        manualQuality: true,
      ),
    );
    await cell.session?.selectQuality(quality);
  }

  /// Empties a cell at once; native release finishes in the background (CEL-7).
  void close(int index) {
    final cell = state.cells[index];
    _cellEpochs[index] = ++_epoch;
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
    }
    state = state.copyWith(target: index);
  }

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

  /// Empties all cells synchronously so the videos unmount before the page pops.
  void clearForExit() {
    _epoch++;
    final old = state.cells;
    state = state.copyWith(cells: [for (final _ in old) const MultiviewCell()]);
    for (final cell in old) {
      unawaited(_release(cell));
    }
  }
}

/// The multiview page state; disposed with the page.
final NotifierProvider<MultiviewController, MultiviewState> multiviewProvider =
    NotifierProvider.autoDispose<MultiviewController, MultiviewState>(MultiviewController.new);
