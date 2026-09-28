import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart' show MpvEngine;
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live_app/core/error_view.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/follow_status.dart';
import 'package:pure_live_app/features/me/history_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';
import 'package:share_plus/share_plus.dart';

/// Q-12: quality and line in one panel, two columns when there is room. The
/// panel follows the session, so a switch in progress shows.
/// [onQualityPicked] hears a quality the user picked.
Future<void> showQualityLineSheet(
  BuildContext context,
  PlaybackSession session, {
  ValueChanged<Quality>? onQualityPicked,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
  builder: (context) => _QualityLinePanel(session: session, onQualityPicked: onQualityPicked),
);

class _QualityLinePanel extends StatefulWidget {
  const new({required this.session, this.onQualityPicked});

  final PlaybackSession session;
  final ValueChanged<Quality>? onQualityPicked;

  @override
  State<_QualityLinePanel> createState() => _QualityLinePanelState();
}

class _QualityLinePanelState extends State<_QualityLinePanel> {
  late PlaybackState _state = widget.session.state;
  StreamSubscription<PlaybackState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.session.states.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final switching = const {PlaybackPhase.resolving, PlaybackPhase.connecting}.contains(_state.phase);
    final line = _state.line;
    final limited = line?.confirmed != null && line!.confirmed != line.requested;
    final qualities = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.multiview.quality, style: theme.textTheme.titleSmall),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [
            for (final quality in _state.qualities)
              ChoiceChip(
                label: Text(quality.label),
                selected: quality == _state.quality,
                onSelected: switching && quality == _state.quality
                    ? null
                    : (_) {
                        // Q-8: the last choice wins; choosing the current one cancels a switch.
                        unawaited(widget.session.selectQuality(quality));
                        widget.onQualityPicked?.call(quality);
                        Navigator.pop(context);
                      },
              ),
          ],
        ),
        if (limited) ...[
          const SizedBox(height: Space.s1),
          Text(t.room.platformLimited(quality: line.confirmed!.label), style: theme.textTheme.bodySmall),
        ],
      ],
    );
    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.multiview.line, style: theme.textTheme.titleSmall),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [
            for (final (index, option) in _state.lines.indexed)
              ChoiceChip(
                label: Text(t.multiview.lineN(n: index + 1)),
                selected: option.lineId == line?.lineId,
                onSelected: (_) {
                  unawaited(widget.session.selectLine(option.lineId));
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ],
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (switching) const LinearProgressIndicator(),
            const SizedBox(height: Space.s2),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 480
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: qualities),
                        const SizedBox(width: Space.s4),
                        Expanded(child: lines),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        qualities,
                        const SizedBox(height: Space.s4),
                        lines,
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "画质 · 线路 2" for the control bar (Q-12).
String qualityLineLabel(PlaybackState state) {
  final quality = state.quality?.label ?? t.multiview.quality;
  final index = state.lines.indexWhere((line) => line.lineId == state.line?.lineId);
  return state.lines.length > 1 && index >= 0 ? t.room.qualityLine(quality: quality, n: index + 1) : quality;
}

/// What the quick panel asked for (T-07).
enum QuickAction {
  /// Open the quality and line panel.
  qualityLine,

  /// Turn on-video danmaku on or off.
  toggleDanmaku,

  /// Save a picture of the current frame.
  screenshot,

  /// Open the sleep timer.
  sleepTimer,

  /// Audio only on or off.
  audioOnly,

  /// Fit inside.
  fitContain,

  /// Fill and crop.
  fitCover,

  /// Stretch.
  fitFill,
}

/// The long-press quick panel (T-07, principles §6.1): 画质, 线路, 弹幕开关,
/// 截图, 定时关闭, 画面比例. The first one ever explains itself when
/// [explain] (principles §6.5).
Future<QuickAction?> showQuickPanel(
  BuildContext context, {
  required String qualityLabel,
  required bool danmakuAvailable,
  required bool danmakuShown,
  required bool canScreenshot,
  required bool audioOnly,
  required VideoFit fit,
  bool explain = false,
}) {
  final hint = explain;
  return showModalBottomSheet<QuickAction>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
    builder: (context) {
      final theme = Theme.of(context);
      Widget action(QuickAction value, LiveIcons icon, String label, {bool enabled = true, bool selected = false}) =>
          SizedBox(
            width: 88,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.r3),
              onTap: enabled ? () => Navigator.pop(context, value) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s2),
                child: Column(
                  children: [
                    LiveIcon(
                      icon,
                      filled: selected,
                      color: enabled ? (selected ? theme.colorScheme.primary : null) : theme.disabledColor,
                    ),
                    const SizedBox(height: Space.s1),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium!.copyWith(color: enabled ? null : theme.disabledColor),
                    ),
                  ],
                ),
              ),
            ),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hint)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s3),
                  child: Text(t.room.quickPanelHint, style: theme.textTheme.bodySmall),
                ),
              Wrap(
                alignment: WrapAlignment.spaceAround,
                children: [
                  action(QuickAction.qualityLine, LiveIcons.quality, qualityLabel),
                  if (danmakuAvailable)
                    action(
                      QuickAction.toggleDanmaku,
                      LiveIcons.danmaku,
                      danmakuShown ? t.multiview.danmakuOff : t.danmaku.turnOn,
                      selected: danmakuShown,
                    ),
                  action(QuickAction.screenshot, LiveIcons.screenshot, t.room.screenshot, enabled: canScreenshot),
                  action(QuickAction.sleepTimer, LiveIcons.sleepTimer, t.room.sleepTimer),
                  action(
                    QuickAction.audioOnly,
                    LiveIcons.audioOnly,
                    audioOnly ? t.room.restoreVideo : t.room.audioOnly,
                    selected: audioOnly,
                  ),
                ],
              ),
              const SizedBox(height: Space.s3),
              Text(t.room.aspect, style: theme.textTheme.titleSmall),
              const SizedBox(height: Space.s2),
              SegmentedButton<QuickAction>(
                segments: [
                  ButtonSegment(value: QuickAction.fitContain, label: Text(t.room.fit.contain)),
                  ButtonSegment(value: QuickAction.fitCover, label: Text(t.room.fit.cover)),
                  ButtonSegment(value: QuickAction.fitFill, label: Text(t.room.fit.fill)),
                ],
                selected: {
                  switch (fit) {
                    VideoFit.cover => QuickAction.fitCover,
                    VideoFit.fill => QuickAction.fitFill,
                    _ => QuickAction.fitContain,
                  },
                },
                onSelectionChanged: (value) => Navigator.pop(context, value.first),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The fit a quick-panel action picks, or null.
VideoFit? fitOfQuickAction(QuickAction action) => switch (action) {
  QuickAction.fitContain => VideoFit.contain,
  QuickAction.fitCover => VideoFit.cover,
  QuickAction.fitFill => VideoFit.fill,
  _ => null,
};

/// Items of the ⋮ menu (F-ROOM-12, principles §5.2).
enum RoomMenuAction {
  /// 切换直播间 (F-ROOM-11).
  switchRoom,

  /// 打开原站 (F-ROOM-18).
  openSite,

  /// 分享 (F-SHR-01).
  share,

  /// 复制直链.
  copyStreamUrl,

  /// 定时关闭 (F-TMR-01).
  sleepTimer,

  /// 房间音量 (F-ROOM-13).
  volume,

  /// 弹幕设置 (F-DM-02).
  danmakuSettings,

  /// 加入多画面.
  multiview,

  /// 快捷键 (D-16).
  keys,

  /// 投屏 (F-CAST-01).
  cast,

  /// 在 App 中打开 (F-ROOM-18, Android).
  openApp,

  /// 新窗口打开 (F-WIN-02, Windows).
  newWindow,
}

/// The ⋮ menu entries for this platform.
List<PopupMenuEntry<RoomMenuAction>> roomMenuEntries({
  required bool desktop,
  required bool danmakuAvailable,
  bool newWindow = false,
  bool openApp = false,
}) {
  PopupMenuItem<RoomMenuAction> item(RoomMenuAction value, LiveIcons icon, String label) => PopupMenuItem(
    value: value,
    child: ListTile(leading: LiveIcon(icon), title: Text(label), contentPadding: EdgeInsets.zero),
  );
  return [
    item(RoomMenuAction.switchRoom, LiveIcons.switchRoom, t.room.switchRoom),
    item(RoomMenuAction.openSite, LiveIcons.openSite, t.common.openSite),
    if (openApp) item(RoomMenuAction.openApp, LiveIcons.openInApp, t.room.openInApp),
    item(RoomMenuAction.share, LiveIcons.share, t.room.share),
    item(RoomMenuAction.cast, LiveIcons.cast, t.room.cast),
    item(RoomMenuAction.copyStreamUrl, LiveIcons.link, t.room.copyStreamUrl),
    item(RoomMenuAction.sleepTimer, LiveIcons.sleepTimer, t.room.sleepTimer),
    item(RoomMenuAction.volume, LiveIcons.volume, t.room.roomVolume),
    if (danmakuAvailable) item(RoomMenuAction.danmakuSettings, LiveIcons.tune, t.danmaku.settings),
    item(RoomMenuAction.multiview, LiveIcons.multiview, t.room.addToMultiview),
    if (desktop) item(RoomMenuAction.keys, LiveIcons.shortcuts, t.room.shortcuts),
    // F-WIN-02: Windows only.
    if (newWindow) item(RoomMenuAction.newWindow, LiveIcons.newWindow, t.room.openInNewWindow),
  ];
}

/// F-SHR-01: the room's share code (3.x-compatible): the system share sheet
/// on phones, the clipboard on desktops (and when the sheet fails).
Future<void> shareRoom(BuildContext context, RoomDetail detail) async {
  final card = detail.card;
  final code = ShareCode(
    card.ref,
    title: card.title,
    anchorName: card.anchorName,
    link: detail.link.toString(),
    cover: card.cover?.toString() ?? '',
    avatar: (detail.avatar ?? card.avatar)?.toString() ?? '',
  ).encode();
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final box = context.findRenderObject();
      await SharePlus.instance.share(
        ShareParams(
          text: code,
          subject: t.room.shareSubject(name: card.anchorName),
          // iPad anchors the sheet to the button.
          sharePositionOrigin: box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null,
        ),
      );
      return;
    } on Object {
      // No share sheet: fall back to the clipboard.
    }
  }
  await Clipboard.setData(ClipboardData(text: code));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.room.shareCodeCopied)));
  }
}

/// 复制直链: the stream URL playing now.
Future<void> copyStreamUrl(BuildContext context, PlaybackState state) async {
  final url = state.line?.url;
  final messenger = ScaffoldMessenger.of(context);
  if (url == null) {
    messenger.showSnackBar(SnackBar(content: Text(t.room.noStreamYet)));
    return;
  }
  await Clipboard.setData(ClipboardData(text: url.toString()));
  messenger.showSnackBar(SnackBar(content: Text(t.room.streamUrlCopied)));
}

/// Whether the session can take a screenshot (mpv only).
bool canScreenshot(PlaybackSession session) => session.engine is MpvEngine && session.state.hasPicture;

/// Saves the current frame as PNG: the Downloads folder on desktops, the
/// app's external pictures folder on Android (no gallery entry: that needs a
/// MediaStore plugin). Returns the file, or null when there is no picture.
Future<File?> saveScreenshot(PlaybackSession session, RoomDetail detail) async {
  final engine = session.engine;
  if (engine is! MpvEngine) return null;
  final bytes = await engine.player.screenshot(format: 'image/png');
  if (bytes == null || bytes.isEmpty) return null;
  final base = Platform.isAndroid
      ? await getExternalStorageDirectory()
      : await getDownloadsDirectory().catchError((Object _) => null);
  final root = base ?? await getApplicationDocumentsDirectory();
  final folder = Directory('${root.path}${Platform.pathSeparator}PureLive');
  await folder.create(recursive: true);
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final name = detail.card.anchorName.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  final file = File('${folder.path}${Platform.pathSeparator}${name}_$stamp.png');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// F-ROOM-11: live follows and history, tap to switch. Returns the room.
Future<RoomRef?> showSwitchRoomSheet(BuildContext context, {required RoomRef current}) => showModalBottomSheet<RoomRef>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
  builder: (context) => FractionallySizedBox(heightFactor: 0.7, child: _SwitchRoomPanel(current: current)),
);

class _SwitchRoomPanel extends ConsumerWidget {
  const new({required this.current});

  final RoomRef current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follows = ref.watch(followsProvider);
    final history = ref.watch(historyProvider);
    final session = FollowSession.of(ref.watch(followRefreshProvider));
    final sites = ref.watch(sitesProvider);
    // F-ROOM-11: rooms being recorded now (a snapshot; the panel is short-lived).
    final recording = [
      for (final task in ref.read(recordManagerProvider).tasks)
        if (task.state.active)
          StoredRoom(
            ref: task.room,
            anchorName: task.snapshot.anchorName,
            title: task.snapshot.title,
            avatar: task.snapshot.avatar,
            cover: task.snapshot.cover,
            lastState: LiveState.live,
            updatedAt: task.createdAt,
          ),
    ];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget list(AsyncValue<List<StoredRoom>> rooms, String empty) => rooms.when(
      loading: () => const SkeletonList(),
      error: (error, _) => ErrorView(
        error,
        title: t.common.loadFailed,
        compact: true,
        onRetry: () {
          ref
            ..invalidate(followsProvider)
            ..invalidate(historyProvider);
        },
      ),
      data: (rooms) {
        final shown = [
          for (final room in rooms)
            if (room.ref != current) room,
        ];
        if (shown.isEmpty) return MessageView(title: empty);
        return ListView.builder(
          itemCount: shown.length,
          itemBuilder: (context, index) {
            final room = shown[index];
            final live = room.lastState == LiveState.live;
            // principles §3.4: the streamer's avatar leads; the logo names
            // the source beside the title.
            return ListTile(
              leading: InitialAvatar(
                name: room.anchorName,
                seed: room.ref.key,
                image: networkImage(room.avatar, logicalWidth: 40, devicePixelRatio: dpr),
              ),
              title: Text(room.anchorName.isEmpty ? room.ref.roomId : room.anchorName, maxLines: 1),
              subtitle: Row(
                children: [
                  PlatformLogo(platformId: room.ref.platform),
                  const SizedBox(width: Space.s1),
                  Expanded(
                    child: Text(
                      room.title.isEmpty ? (platformNames[room.ref.platform] ?? room.ref.platform) : room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              trailing: live ? const LiveBadge() : null,
              onTap: () => Navigator.pop(context, room.ref),
            );
          },
        );
      },
    );
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: t.follows.liveFollows),
              Tab(text: t.recording.state.recording),
              Tab(text: t.app.history),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                list(
                  follows.whenData(
                    // F-FAV-03: live as this run checked it, not as stored.
                    (all) => [
                      for (final follow in all)
                        if (session.statusOf(follow, supported: sites.containsKey(follow.ref.platform)) ==
                            FollowStatus.live)
                          follow.room,
                    ],
                  ),
                  t.room.noLiveFollows,
                ),
                list(AsyncValue.data(recording), t.room.noRecordingRooms),
                list(history.whenData((all) => [for (final entry in all) entry.room]), t.room.noHistory),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// F-ROOM-13: the room volume. It sets the player's volume (never the
/// device's, INV-ROOM-03); desktops remember it per room; the button stores
/// it as the platform default.
Future<void> showRoomVolumeDialog(
  BuildContext context, {
  required double volume,
  required ValueChanged<double> onChanged,
  required VoidCallback onSaveDefault,
  required bool desktop,
}) => showDialog<void>(
  context: context,
  builder: (context) {
    var value = volume;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(t.room.roomVolume),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                LiveIcon(value == 0 ? LiveIcons.mute : LiveIcons.volume, filled: value == 0),
                Expanded(
                  child: Slider(
                    value: value,
                    divisions: 20,
                    label: '${(value * 100).round()}%',
                    onChanged: (next) {
                      setState(() => value = next);
                      onChanged(next);
                    },
                  ),
                ),
                SizedBox(width: 44, child: Text('${(value * 100).round()}%', textAlign: TextAlign.end)),
              ],
            ),
            Text(
              desktop ? t.room.volumeRemembered : t.room.volumePlayerOnly,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              onSaveDefault();
              Navigator.pop(context);
            },
            child: Text(desktop ? t.room.setDefaultVolume : t.room.setPhoneDefaultVolume),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(t.common.done)),
        ],
      ),
    );
  },
);

/// D-16: the keyboard shortcuts.
Future<void> showKeyHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(t.room.shortcuts),
    content: SingleChildScrollView(
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        children: [
          for (final (key, action) in [
            (t.room.key.space, t.room.key.playPause),
            (t.room.key.fullscreenKeys, t.room.key.fullscreen),
            ('Esc', t.room.key.escape),
            ('T', t.room.key.theater),
            ('C', t.room.key.chat),
            ('M', t.room.key.mute),
            (t.room.key.volumeKeys, t.room.key.volume),
            ('D', t.room.key.danmaku),
            ('Q / L', t.room.key.qualityLine),
            (t.room.key.refreshKeys, t.common.refresh),
            ('?', t.room.key.help),
          ])
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: Space.s4, bottom: Space.s2),
                  child: Text(key, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: Text(action),
                ),
              ],
            ),
        ],
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.close))],
  ),
);

/// F-ROOM-18: the room in the platform's own Android app, where 3.x knew
/// how (its `RoomExternalOpener` links); null otherwise.
Uri? nativeAppLink(RoomDetail detail) {
  final room = detail.ref;
  final id = Uri.encodeComponent(room.roomId);
  final keys = detail.danmakuKeys;
  String? key(String name) {
    final value = keys[name]?.trim();
    return value == null || value.isEmpty ? null : Uri.encodeQueryComponent(value);
  }

  final link = switch (room.platform) {
    'bilibili' => 'bilibili://live/$id',
    'douyu' => 'douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D$id',
    'douyin' => switch (key('roomId')) {
      final roomId? => 'snssdk1128://webcast_room?room_id=$roomId',
      null => null,
    },
    'huya' => switch (int.tryParse(keys['subSid'] ?? '')) {
      final sid? when sid > 0 =>
        'yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html'
            '%3Fhyaction%3Dlive%26channelid%3D$sid%26subid%3D$sid%26liveuid%3D$sid%26screentype%3D1%26sourcetype%3D0'
            '%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide',
      _ => null,
    },
    'kuaishou' => switch (key('liveStreamId')) {
      final stream? =>
        'kwai://liveaggregatesquare?liveStreamId=$stream&recoStreamId=$stream&recoLiveStreamId=$stream'
            '&liveSquareSource=28&path=/rest/n/live/feed/sharePage/slide/more&mt_product=H5_OUTSIDE_CLIENT_SHARE',
      null => null,
    },
    _ => null,
  };
  return link == null ? null : Uri.parse(link);
}
