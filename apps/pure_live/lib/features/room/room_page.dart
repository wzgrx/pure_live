import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart' show AudienceKind, DanmakuEvent;
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/chat_actions.dart';
import 'package:pure_live_app/features/danmaku/chat_panel.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_settings.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/danmaku/on_video.dart';
import 'package:pure_live_app/features/danmaku/room_danmaku.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/iptv/iptv_room.dart';
import 'package:pure_live_app/features/room/gestures.dart';
import 'package:pure_live_app/features/room/playback.dart';
import 'package:pure_live_app/features/room/player_view.dart';
import 'package:pure_live_app/features/room/presentation.dart';
import 'package:pure_live_app/features/room/room_layout.dart';
import 'package:pure_live_app/features/room/room_menus.dart';
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/features/room/tv_room.dart';
import 'package:pure_live_app/l10n/strings.dart';
import 'package:url_launcher/url_launcher.dart';

/// A room's details.
final FutureProviderFamily<RoomDetail, RoomRef> roomDetailProvider = FutureProvider.autoDispose
    .family<RoomDetail, RoomRef>((ref, room) async {
      final detail = await ref.watch(sitesProvider)[room.platform]!.rooms.detail(room);
      // Opening a room records it in the history (IPTV channels excepted,
      // F-HIS-01) and refreshes a followed card.
      final store = ref.read(storeProvider);
      final snapshot = RoomSnapshot.fromDetail(detail);
      if (room.platform != 'iptv') await store.history.record(snapshot);
      await store.rooms.update([snapshot]);
      return detail;
    });

/// Whether a room is followed.
final StreamProviderFamily<bool, RoomRef> isFollowedProvider = StreamProvider.autoDispose.family<bool, RoomRef>(
  (ref, room) => ref.watch(storeProvider).follows.watchContains(room),
);

/// The room page (spec/modules/live-room.md): one presentation value
/// (inline, theater, fullscreen, portrait fullscreen) from which the layout
/// and the platform state follow (PS-1); one video surface moved between
/// layouts (PS-3); the room's chat; the keyboard (§3.4) and the back chain
/// (§3.6: panel → fullscreen or theater → leave). Switching rooms happens in
/// place: same session and surface, new source and chat.
class RoomPage extends ConsumerStatefulWidget {
  const new({required this.room, this.origin, super.key});

  /// The room.
  final RoomRef room;

  /// The list the room was opened from; up and down, PageUp and PageDown and
  /// the optional portrait swipe switch within it (F-NEW-04). Null: the live
  /// follows.
  final RoomOrigin? origin;

  @override
  ConsumerState<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends ConsumerState<RoomPage> {
  late RoomRef _room = widget.room;
  RoomDetail? _detail;
  late final PlaybackSession _session;
  StreamSubscription<PlaybackState>? _states;
  final GlobalKey<PlayerViewState> _videoKey = GlobalKey();
  final DanmakuController _overlayController = DanmakuController();
  late final ControllerOnVideo _overlay = ControllerOnVideo(_overlayController);
  RoomDanmaku? _danmaku;
  List<BlockRule> _rules = const [];

  RoomPresentation _presentation = RoomPresentation.inline;
  RoomPresentation _returnTo = RoomPresentation.inline;
  bool _transitioning = false;
  bool _restorePortrait = false;
  bool _rotationFullscreen = false;
  bool _portraitSource = false;
  bool _landscapeSource = false;
  bool _chatOpen = true;
  bool _fullscreenChat = false;
  double _chatWidth = Sizes.chatWidth;
  Orientation? _orientation;
  Timer? _defaultFullscreen;
  bool _adoptedOnce = false;

  /// TV mode (live-room §3.5): always fullscreen, the remote layer on top.
  bool _tv = false;

  bool get _touch => touchPlatform;

  @override
  void initState() {
    super.initState();
    // Listening keeps the auto-disposed session alive for the page's life.
    _session = ref.listenManual(playbackSessionProvider, (_, _) {}).read();
    _states = _session.states.listen(_onPlayback);
    final prefs = ref.read(danmakuPrefsProvider);
    _overlayController
      ..style = prefs.style
      ..budget = prefs.budget;
    _rules = ref.read(blockRulesProvider).value ?? const [];
    // Without a list of its own the room switches in the live follows; keep
    // them loaded so the first switch finds them (T-05).
    if (widget.origin == null) ref.listenManual(followsProvider, (_, _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tv = TvScope.of(context).enabled;
    if (tv != _tv) {
      // The room is always fullscreen on TV; there is nothing to lock or
      // hide on the platform side.
      _tv = tv;
      _presentation = tv ? RoomPresentation.fullscreen : RoomPresentation.inline;
      _returnTo = RoomPresentation.inline;
    }
    // T-09: on a phone, turning a landscape stream sideways enters
    // fullscreen; turning back leaves a fullscreen entered that way.
    final orientation = MediaQuery.orientationOf(context);
    final previous = _orientation;
    _orientation = orientation;
    if (previous == null || previous == orientation || !_isPhone) return;
    if (orientation == Orientation.landscape &&
        _presentation == RoomPresentation.inline &&
        !_portraitSource &&
        _detail?.state == LiveState.live) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_present(RoomPresentation.fullscreen, byRotation: true));
      });
    } else if (orientation == Orientation.portrait &&
        _presentation == RoomPresentation.fullscreen &&
        _rotationFullscreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_present(_returnTo));
      });
    }
  }

  bool get _isPhone => !_tv && _touch && MediaQuery.sizeOf(context).shortestSide < 600;

  @override
  void dispose() {
    _defaultFullscreen?.cancel();
    unawaited(_states?.cancel());
    final danmaku = _danmaku;
    _danmaku = null;
    if (danmaku != null) {
      danmaku.overlay = null;
      unawaited(danmaku.dispose());
    }
    _overlayController.dispose();
    if (_presentation != RoomPresentation.inline && !_tv) {
      unawaited(
        applyPresentation(
          PresentationEffects(presentation: RoomPresentation.inline, restorePortrait: _restorePortrait),
          desktop: !_touch,
        ),
      );
    }
    super.dispose();
  }

  // ------------------------------------------------------------- playback

  void _onPlayback(PlaybackState state) {
    if (!mounted) return;
    _danmaku?.setPlaying(playing: state.phase == PlaybackPhase.playing);
    final orientation = state.geometry.orientation;
    final portrait = orientation == VideoOrientation.portrait;
    final landscape = orientation == VideoOrientation.landscape;
    if (portrait != _portraitSource || landscape != _landscapeSource) {
      setState(() {
        _portraitSource = portrait;
        _landscapeSource = landscape;
      });
      // REG-ROOM-029: a portrait fullscreen whose source turns landscape leaves.
      if (landscape && _presentation == RoomPresentation.portraitFullscreen) {
        unawaited(_present(RoomPresentation.inline));
      }
    }
  }

  // ------------------------------------------------------------- detail

  /// Takes a newly loaded detail. Runs during build (no setState): a new room
  /// gets a new chat (CONN-4); the same room keeps it.
  void _adopt(RoomDetail detail) {
    final previous = _detail;
    _detail = detail;
    final prefs = ref.read(danmakuPrefsProvider);
    final live = detail.state != LiveState.offline;
    if (previous == null || previous.ref != detail.ref) {
      final old = _danmaku;
      if (old != null) {
        old.overlay = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(old.dispose()));
      }
      _danmaku = RoomDanmaku(
        source: ref.read(danmakuSourceProvider),
        room: detail,
        filters: filterSettingsFor(prefs, _rules),
        enabled: prefs.enabled && live,
        overlay: _overlay,
        overlayVisible: !prefs.hidden,
      )..setPlaying(playing: _session.state.phase == PlaybackPhase.playing);
    } else {
      _danmaku?.setEnabled(enabled: prefs.enabled && live);
    }
    if (detail.state == LiveState.offline) {
      // LAY-5: offline or banned leaves fullscreen and theater (not on TV,
      // where the room is always fullscreen).
      if (_presentation != RoomPresentation.inline && !_tv) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_present(RoomPresentation.inline));
        });
      }
      if (previous != null && previous.ref == detail.ref && previous.state == LiveState.live) {
        unawaited(_session.close());
      }
    }
    if (!_adoptedOnce) {
      _adoptedOnce = true;
      // F-ROOM-15: fullscreen 1 s after entering, when the setting is on.
      if (live && !_tv && ref.read(storeProvider).settings.get(Settings.fullScreenDefault)) {
        _defaultFullscreen = Timer(const Duration(seconds: 1), () {
          if (mounted && _presentation == RoomPresentation.inline) _toggleFullscreen();
        });
      }
    }
  }

  // ------------------------------------------------------------- presentation

  /// Changes the presentation. INV-ROOM-07: a change in progress ignores new
  /// requests. PS-2: the lock resets (the player does it on the new value).
  Future<void> _present(RoomPresentation next, {bool forceLandscape = false, bool byRotation = false}) async {
    if (_tv || _transitioning || next == _presentation) return;
    _transitioning = true;
    final previous = _presentation;
    if (next.isFullscreen && !previous.isFullscreen) _returnTo = previous;
    final restore = !next.isFullscreen && _restorePortrait;
    // INV-ROOM-04: only a forced-landscape fullscreen records the restore;
    // any other fullscreen clears a pending one.
    _restorePortrait = next == RoomPresentation.fullscreen && forceLandscape;
    _rotationFullscreen = byRotation && next == RoomPresentation.fullscreen;
    final phone = _isPhone;
    setState(() => _presentation = next);
    if (next == RoomPresentation.portraitFullscreen) _offerSwitchGesture();
    try {
      // A platform that never answers must not block every later change.
      await applyPresentation(
        PresentationEffects(
          presentation: next,
          lockLandscape:
              phone && next == RoomPresentation.fullscreen && !byRotation && (forceLandscape || !_portraitSource),
          lockPortrait: phone && next == RoomPresentation.portraitFullscreen,
          restorePortrait: phone && restore,
        ),
        desktop: !_touch,
      ).timeout(const Duration(seconds: 1), onTimeout: () {});
    } finally {
      _transitioning = false;
    }
  }

  /// T-02 / D-02 / F / the fullscreen button.
  void _toggleFullscreen() {
    if (_tv) return;
    final target = doubleTapTarget(
      current: _presentation,
      locked: false,
      portraitCondition: _touch && _portraitSource,
      returnTo: _returnTo,
    );
    if (target != null) unawaited(_present(target));
  }

  bool _canTheater(Size size) {
    final layout = WindowLayout(size);
    return layout.width.atLeast(WidthClass.large) && !layout.isShortLandscape;
  }

  void _toggleTheater() {
    if (!_canTheater(MediaQuery.sizeOf(context))) return;
    unawaited(_present(_presentation == RoomPresentation.theater ? RoomPresentation.inline : RoomPresentation.theater));
  }

  void _toggleChat() {
    setState(() {
      if (_effective.isFullscreen) {
        _fullscreenChat = !_fullscreenChat;
      } else {
        _chatOpen = !_chatOpen;
      }
    });
  }

  /// A phone held landscape shows the fullscreen layout even when the
  /// presentation is inline (principles §5.2: 高度紧凑 enters fullscreen).
  RoomPresentation get _effective {
    if (_presentation != RoomPresentation.inline) return _presentation;
    return WindowLayout(MediaQuery.sizeOf(context)).isShortLandscape ? RoomPresentation.fullscreen : _presentation;
  }

  /// §3.6 after the panels (the navigator closes those first): fullscreen
  /// returns to where it came from, theater to inline, inline leaves.
  void _back() {
    if (_tv) {
      // TV-06: the remote layer closes its panel or control row first.
      Navigator.of(context).maybePop();
      return;
    }
    switch (_presentation) {
      case RoomPresentation.fullscreen || RoomPresentation.portraitFullscreen:
        unawaited(_present(_returnTo));
      case RoomPresentation.theater:
        unawaited(_present(RoomPresentation.inline));
      case RoomPresentation.inline:
        Navigator.of(context).maybePop();
    }
  }

  // ------------------------------------------------------------- actions

  Future<void> _switchRoom() async {
    final room = await showSwitchRoomSheet(context, current: _room);
    if (room == null || !mounted || room == _room) return;
    setState(() => _room = room);
  }

  /// The list to switch in: where the room was opened from, else the live
  /// follows in the follows page's order (T-05). Only what is loaded.
  List<RoomEntry> _switchEntries() {
    final origin = widget.origin;
    if (origin != null && origin.entries.isNotEmpty) return origin.entries;
    return liveFollowEntries(ref.read(followsProvider).value ?? const []);
  }

  /// F-NEW-04: the previous (-1) or next (+1) live room of the list, in
  /// place like [_switchRoom], with a short hint; the ends say so and do not
  /// wrap around.
  void _stepRoom(int step) {
    final entries = _switchEntries();
    final target = neighborRoom(entries, _room, step);
    final player = _videoKey.currentState;
    if (target == null) {
      final text = entries.isEmpty ? '没有可以切换的开播直播间' : (step < 0 ? '已经是第一个了' : '已经是最后一个了');
      player?.showHint(step < 0 ? Icons.vertical_align_top : Icons.vertical_align_bottom, text);
      return;
    }
    final position = entries.indexOf(target) + 1;
    player?.showHint(
      Icons.swap_vert,
      '${target.label}  $position/${entries.length}',
      duration: const Duration(seconds: 2),
    );
    setState(() => _room = target.ref);
  }

  /// principles §6.1: the first portrait fullscreen with the swipe off says
  /// once that it can be turned on.
  void _offerSwitchGesture() {
    if (!_touch || ref.read(switchRoomGestureSetting) || ref.read(appPrefsProvider).switchGestureHinted) return;
    unawaited(ref.read(appPrefsProvider.notifier).markSwitchGestureHinted().catchError((Object _) {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _videoKey.currentState?.showHint(
        Icons.swipe_vertical,
        '可以在 设置 › 播放 里开启上下滑切换直播间',
        duration: const Duration(seconds: 3),
      );
    });
  }

  void _block(BlockKind kind, String value) {
    _danmaku?.block(kind, value);
    fireAndForget(ref.read(blockRuleWriterProvider).add(kind, value));
  }

  void _unblock(BlockKind kind, String value) => fireAndForget(ref.read(blockRuleWriterProvider).remove(kind, value));

  Future<void> _openLine(DanmakuEvent line) =>
      showChatLineActions(context, line: line, onBlock: _block, onUnblock: _unblock);

  Future<void> _openDanmakuSettings() async {
    final player = _videoKey.currentState;
    if (player != null) {
      await player.withPanel(() => showDanmakuSettingsSheet(context));
    } else {
      await showDanmakuSettingsSheet(context);
    }
  }

  Map<ShortcutActivator, VoidCallback> get _keys {
    PlayerViewState? player() => _videoKey.currentState;
    return {
      const SingleActivator(LogicalKeyboardKey.space): () => player()?.togglePlay(),
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () => player()?.togglePlay(),
      const SingleActivator(LogicalKeyboardKey.mediaPlay): () => unawaited(_session.play()),
      const SingleActivator(LogicalKeyboardKey.mediaPause): () => unawaited(_session.pause()),
      const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false): _back,
      // TV: the room is always fullscreen and the D-pad switches rooms
      // (D-10 "TV 模式除外"; the remote layer takes the arrows).
      if (!_tv) ...{
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
        const SingleActivator(LogicalKeyboardKey.keyT): _toggleTheater,
        const SingleActivator(LogicalKeyboardKey.keyC): _toggleChat,
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => player()?.changeVolume(0.05),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => player()?.changeVolume(-0.05),
      },
      const SingleActivator(LogicalKeyboardKey.keyM): () => player()?.toggleMute(),
      const SingleActivator(LogicalKeyboardKey.keyD): () => player()?.toggleDanmaku(),
      const SingleActivator(LogicalKeyboardKey.keyQ): () => unawaited(player()?.chooseQualityLine()),
      const SingleActivator(LogicalKeyboardKey.keyL): () => unawaited(player()?.chooseQualityLine()),
      const SingleActivator(LogicalKeyboardKey.keyR): () => player()?.refresh(),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => player()?.refresh(),
      const SingleActivator(LogicalKeyboardKey.f5): () => player()?.refresh(),
      const CharacterActivator('?'): () => unawaited(showKeyHelp(context)),
      // F-NEW-04: the previous or next room of the list; PageUp and PageDown
      // on keyboards (principles §6.2), the channel keys of TV remotes (§6.3).
      const SingleActivator(LogicalKeyboardKey.pageUp, includeRepeats: false): () => _stepRoom(-1),
      const SingleActivator(LogicalKeyboardKey.pageDown, includeRepeats: false): () => _stepRoom(1),
      const SingleActivator(LogicalKeyboardKey.channelUp, includeRepeats: false): () => _stepRoom(-1),
      const SingleActivator(LogicalKeyboardKey.channelDown, includeRepeats: false): () => _stepRoom(1),
    };
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    ref.watch(playbackSessionProvider);
    ref.listen(danmakuPrefsProvider, (previous, next) {
      _overlayController
        ..style = next.style
        ..budget = next.budget;
      final danmaku = _danmaku;
      if (danmaku == null) return;
      danmaku
        ..setEnabled(enabled: next.enabled && (_detail?.state ?? LiveState.offline) != LiveState.offline)
        ..setOverlayVisible(visible: !next.hidden)
        ..setFilters(filterSettingsFor(next, _rules));
    });
    ref.listen(blockRulesProvider, (_, next) {
      final rules = next.value;
      if (rules == null) return;
      _rules = rules;
      _danmaku?.setFilters(filterSettingsFor(ref.read(danmakuPrefsProvider), rules));
    });
    ref.listen(roomDetailProvider(_room), (_, next) {
      // A switch to a room that fails to load stops the previous room's stream.
      if (next.hasError && _detail != null && _detail!.ref != _room) unawaited(_session.close());
    });
    final async = ref.watch(roomDetailProvider(_room));
    final fresh = async.value;
    if (fresh != null && !identical(fresh, _detail)) _adopt(fresh);
    final detail = _detail;
    final prefs = ref.watch(danmakuPrefsProvider);
    final effective = _effective;
    final dark = effective.isFullscreen || _presentation == RoomPresentation.theater;
    Widget body;
    if (async.hasError && (detail == null || detail.ref != _room)) {
      final text = describeError(async.error!);
      body = Column(
        children: [
          const _TopBar(),
          Expanded(
            child: MessageView.error(
              title: text.title,
              message: text.message,
              onAction: text.retryable ? () => ref.invalidate(roomDetailProvider(_room)) : null,
              secondaryLabel: '返回',
              onSecondary: () => context.pop(),
            ),
          ),
        ],
      );
    } else if (detail == null) {
      body = const Column(
        children: [
          _TopBar(),
          Expanded(child: LoadingView()),
        ],
      );
    } else {
      final size = MediaQuery.sizeOf(context);
      final canTheater = _canTheater(size);
      final wide = WindowLayout(size).width.atLeast(WidthClass.expanded);
      final live = detail.state != LiveState.offline;
      final chat = ChatPanel(
        danmaku: _danmaku,
        enabled: prefs.enabled,
        live: live,
        onLine: (line) => unawaited(_openLine(line)),
        onEnable: () => ref.read(danmakuPrefsProvider.notifier).setEnabled(enabled: true),
        onOpenSettings: () => unawaited(_openDanmakuSettings()),
      );
      final switchGesture = ref.watch(switchRoomGestureSetting);
      final toggleChat = effective.isFullscreen
          ? (effective == RoomPresentation.portraitFullscreen ? null : _toggleChat)
          : (wide && !WindowLayout(size).isShortLandscape ? _toggleChat : null);
      body = RoomLayout(
        presentation: effective,
        chatOpen: effective.isFullscreen ? _fullscreenChat : _chatOpen,
        chatWidth: _chatWidth,
        onChatWidth: (width) => setState(() => _chatWidth = width),
        portraitPanel: _touch && _portraitSource && effective == RoomPresentation.inline,
        onPortraitFullscreen: () => unawaited(_present(RoomPresentation.portraitFullscreen)),
        onForceLandscape: () => unawaited(_present(RoomPresentation.fullscreen, forceLandscape: true)),
        video: PlayerView(
          key: _videoKey,
          detail: detail,
          session: _session,
          presentation: effective,
          overlay: _overlayController,
          danmaku: _danmaku,
          chatOpen: effective.isFullscreen ? _fullscreenChat : _chatOpen,
          onToggleChat: toggleChat,
          onToggleTheater: canTheater && !effective.isFullscreen ? _toggleTheater : null,
          onToggleFullscreen: _toggleFullscreen,
          onBack: _back,
          onSwitchRoom: () => unawaited(_switchRoom()),
          onStepRoom: switchGesture && !_tv ? _stepRoom : null,
          onBlock: _block,
          onOpenDanmakuSettings: prefs.enabled ? () => unawaited(_openDanmakuSettings()) : null,
          tv: _tv,
        ),
        info: _RoomInfo(detail: detail, danmaku: _danmaku),
        chat: chat,
      );
      if (_tv) {
        final followed = ref.watch(isFollowedProvider(detail.ref)).value ?? false;
        body = TvRoomLayer(
          detail: detail,
          session: _session,
          player: _videoKey,
          entries: _switchEntries,
          listLabel: (widget.origin?.entries.isNotEmpty ?? false) ? widget.origin!.label : '开播的关注',
          onStep: _stepRoom,
          onPick: (room) {
            if (room != _room) setState(() => _room = room);
          },
          followed: followed,
          onFollow: () {
            final follows = ref.read(storeProvider).follows;
            unawaited(followed ? follows.unfollow(detail.ref) : follows.follow(RoomSnapshot.fromDetail(detail)));
          },
          child: body,
        );
      }
    }
    return PopScope(
      // §3.6: back leaves fullscreen and theater before the room; on TV the
      // remote layer holds back for its panels (TV-06).
      canPop: _tv || _presentation == RoomPresentation.inline,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_tv) _back();
      },
      child: CallbackShortcuts(
        bindings: _keys,
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: dark ? Colors.black : null,
            body: SafeArea(
              top: !effective.isFullscreen,
              bottom: !effective.isFullscreen,
              left: !effective.isFullscreen,
              right: !effective.isFullscreen,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: IconButton(tooltip: '返回', icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
  );
}

class _RoomInfo extends ConsumerWidget {
  const new({required this.detail, this.danmaku});

  final RoomDetail detail;
  final RoomDanmaku? danmaku;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final card = detail.card;
    final followed = ref.watch(isFollowedProvider(card.ref)).value ?? false;
    final fallback = switch (card.audience) {
      Audience(online: final value?) => (AudienceKind.online, value),
      Audience(popularity: final value?) => (AudienceKind.popularity, value),
      Audience(cumulative: final value?) => (AudienceKind.cumulative, value),
      _ => null,
    };
    final avatar = networkImage(
      detail.avatar ?? card.avatar,
      logicalWidth: 48,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final numeric = LiveTheme.of(context).numeric;
    return Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                foregroundImage: avatar,
                child: Text(card.anchorName.characters.firstOrNull ?? '?'),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.anchorName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        PlatformLogo(platformId: card.ref.platform),
                        const SizedBox(width: Space.s1),
                        Text(platformNames[card.ref.platform] ?? card.ref.platform, style: theme.textTheme.bodySmall),
                        const SizedBox(width: Space.s2),
                        // LST-6: the live figure from the chat, else the card's.
                        if (danmaku case final chat?)
                          AudienceText(audience: chat.audience, fallback: fallback, style: numeric)
                        else if (fallback != null)
                          Text(formatCount(fallback.$2), style: numeric),
                      ],
                    ),
                  ],
                ),
              ),
              if (card.state == LiveState.live) const LiveBadge(),
            ],
          ),
          const SizedBox(height: Space.s3),
          Text(card.title, style: theme.textTheme.bodyLarge),
          if (card.ref.platform == 'iptv') ...[const SizedBox(height: Space.s3), IptvRoomPanel(detail: detail)],
          if (card.area != null) ...[
            const SizedBox(height: Space.s1),
            Text(card.area!, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: Space.s4),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              if (followed)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.favorite, size: 18),
                  label: const Text(S.unfollow),
                  onPressed: () => ref.read(storeProvider).follows.unfollow(card.ref),
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.favorite_border, size: 18),
                  label: const Text(S.follow),
                  onPressed: () => ref.read(storeProvider).follows.follow(RoomSnapshot.fromDetail(detail)),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.grid_view, size: 18),
                label: const Text('加入多画面'),
                onPressed: () => context.push('/multiview', extra: [card.ref]),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text(S.openSite),
                onPressed: () => launchUrl(detail.link, mode: LaunchMode.externalApplication),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.link, size: 18),
                label: const Text(S.copyLink),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: detail.link.toString()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.linkCopied)));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('分享'),
                onPressed: () => shareRoom(context, detail),
              ),
            ],
          ),
          if (detail.introduction case final intro? when intro.trim().isNotEmpty) ...[
            const SizedBox(height: Space.s4),
            Text(intro, style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
