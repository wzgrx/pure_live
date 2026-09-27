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
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/me/history_page.dart';
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
        Text('画质', style: theme.textTheme.titleSmall),
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
          Text('平台限制为 ${line.confirmed!.label}', style: theme.textTheme.bodySmall),
        ],
      ],
    );
    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('线路', style: theme.textTheme.titleSmall),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [
            for (final (index, option) in _state.lines.indexed)
              ChoiceChip(
                label: Text('线路 ${index + 1}'),
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
  final quality = state.quality?.label ?? '画质';
  final index = state.lines.indexWhere((line) => line.lineId == state.line?.lineId);
  return state.lines.length > 1 && index >= 0 ? '$quality · 线路 ${index + 1}' : quality;
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
      Widget action(QuickAction value, IconData icon, String label, {bool enabled = true, bool selected = false}) =>
          SizedBox(
            width: 88,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.r3),
              onTap: enabled ? () => Navigator.pop(context, value) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s2),
                child: Column(
                  children: [
                    Icon(icon, color: enabled ? (selected ? theme.colorScheme.primary : null) : theme.disabledColor),
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
                  child: Text('长按画面打开快捷面板；长按弹幕可以复制或屏蔽', style: theme.textTheme.bodySmall),
                ),
              Wrap(
                alignment: WrapAlignment.spaceAround,
                children: [
                  action(QuickAction.qualityLine, Icons.high_quality_outlined, qualityLabel),
                  if (danmakuAvailable)
                    action(
                      QuickAction.toggleDanmaku,
                      danmakuShown ? Icons.subtitles : Icons.subtitles_off_outlined,
                      danmakuShown ? '关闭弹幕' : '打开弹幕',
                      selected: danmakuShown,
                    ),
                  action(QuickAction.screenshot, Icons.photo_camera_outlined, '截图', enabled: canScreenshot),
                  action(QuickAction.sleepTimer, Icons.bedtime_outlined, '定时关闭'),
                  action(
                    QuickAction.audioOnly,
                    Icons.headphones_outlined,
                    audioOnly ? '恢复画面' : '纯音频',
                    selected: audioOnly,
                  ),
                ],
              ),
              const SizedBox(height: Space.s3),
              Text('画面比例', style: theme.textTheme.titleSmall),
              const SizedBox(height: Space.s2),
              SegmentedButton<QuickAction>(
                segments: const [
                  ButtonSegment(value: QuickAction.fitContain, label: Text('适应')),
                  ButtonSegment(value: QuickAction.fitCover, label: Text('填充')),
                  ButtonSegment(value: QuickAction.fitFill, label: Text('拉伸')),
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

  /// 新窗口打开 (F-WIN-02, Windows).
  newWindow,
}

/// The ⋮ menu entries for this platform.
List<PopupMenuEntry<RoomMenuAction>> roomMenuEntries({
  required bool desktop,
  required bool danmakuAvailable,
  bool newWindow = false,
}) {
  PopupMenuItem<RoomMenuAction> item(RoomMenuAction value, IconData icon, String label) => PopupMenuItem(
    value: value,
    child: ListTile(leading: Icon(icon), title: Text(label), contentPadding: EdgeInsets.zero),
  );
  return [
    item(RoomMenuAction.switchRoom, Icons.swap_horiz, '切换直播间'),
    item(RoomMenuAction.openSite, Icons.open_in_new, '打开原站'),
    item(RoomMenuAction.share, Icons.share_outlined, '分享'),
    item(RoomMenuAction.cast, Icons.cast, '投屏'),
    item(RoomMenuAction.copyStreamUrl, Icons.link, '复制直链'),
    item(RoomMenuAction.sleepTimer, Icons.bedtime_outlined, '定时关闭'),
    item(RoomMenuAction.volume, Icons.volume_up_outlined, '房间音量'),
    if (danmakuAvailable) item(RoomMenuAction.danmakuSettings, Icons.tune, '弹幕设置'),
    item(RoomMenuAction.multiview, Icons.grid_view, '加入多画面'),
    if (desktop) item(RoomMenuAction.keys, Icons.keyboard_outlined, '快捷键'),
    // F-WIN-02: Windows only.
    if (newWindow) item(RoomMenuAction.newWindow, Icons.open_in_browser, '新窗口打开'),
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
          subject: '${card.anchorName}的直播间',
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分享口令已复制，对方在纯粹直播里粘贴即可打开')));
  }
}

/// 复制直链: the stream URL playing now.
Future<void> copyStreamUrl(BuildContext context, PlaybackState state) async {
  final url = state.line?.url;
  final messenger = ScaffoldMessenger.of(context);
  if (url == null) {
    messenger.showSnackBar(const SnackBar(content: Text('还没有拿到直播流')));
    return;
  }
  await Clipboard.setData(ClipboardData(text: url.toString()));
  messenger.showSnackBar(const SnackBar(content: Text('直链已复制，有时效，过期后需要重新复制')));
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
    Widget list(AsyncValue<List<StoredRoom>> rooms, String empty) => rooms.when(
      loading: () => const LoadingView(),
      error: (error, _) => MessageView.error(title: '读取失败', message: '$error'),
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
            return ListTile(
              leading: PlatformLogo(platformId: room.ref.platform, size: 24),
              title: Text(room.anchorName.isEmpty ? room.ref.roomId : room.anchorName, maxLines: 1),
              subtitle: Text(
                room.title.isEmpty ? (platformNames[room.ref.platform] ?? room.ref.platform) : room.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: live ? const LiveBadge() : null,
              onTap: () => Navigator.pop(context, room.ref),
            );
          },
        );
      },
    );
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '开播的关注'),
              Tab(text: '观看历史'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                list(
                  follows.whenData(
                    (all) => [
                      for (final follow in all)
                        if (follow.room.lastState == LiveState.live) follow.room,
                    ],
                  ),
                  '没有开播的关注',
                ),
                list(history.whenData((all) => [for (final entry in all) entry.room]), '还没有观看历史'),
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
        title: const Text('房间音量'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(value == 0 ? Icons.volume_off : Icons.volume_up),
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
            Text(desktop ? '这个直播间会记住这个音量' : '只调节播放器音量，不改动手机的媒体音量', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              onSaveDefault();
              Navigator.pop(context);
            },
            child: Text(desktop ? '设为默认音量' : '设为手机默认音量'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('完成')),
        ],
      ),
    );
  },
);

/// D-16: the keyboard shortcuts.
Future<void> showKeyHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('快捷键'),
    content: SingleChildScrollView(
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        children: [
          for (final (key, action) in const [
            ('空格', '播放 / 暂停'),
            ('F、双击', '全屏 / 退出全屏'),
            ('Esc', '关闭弹层 → 退出全屏或剧场 → 离开直播间'),
            ('T', '剧场模式'),
            ('C', '显示 / 收起聊天栏'),
            ('M', '静音'),
            ('↑ ↓、滚轮', '音量 ±5%'),
            ('D', '弹幕开关'),
            ('Q / L', '画质 / 线路'),
            ('R、F5、Ctrl+R', '刷新'),
            ('?', '快捷键帮助'),
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
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
  ),
);
