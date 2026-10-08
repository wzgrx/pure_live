import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_cast/live_cast.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/platform_services.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/platform_texts.dart';

/// What the stream panel does with the chosen address.
enum StreamUse {
  /// Copies it (3.x "get direct link").
  copy,

  /// Casts it to a DLNA receiver (3.x `castPlayUrlByRoomId`).
  cast,
}

/// Opens "获取直链" ([StreamUse.copy]) or "投屏" ([StreamUse.cast]) for the
/// room of [controller] (docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一 c1, c4): the room's panel, or
/// the same panel in a sheet where there is no room page around [context].
void showStreamPanel(BuildContext context, LiveRoomController controller, StreamUse use) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels != null) {
    panels.open(use == StreamUse.cast ? RoomPanelKind.cast : RoomPanelKind.streamLink);
    return;
  }
  unawaited(
    showRoomPanelSheet(
      context,
      builder: (_, close) => RoomStreamPanel(controller: controller, use: use, onClose: close),
    ),
  );
}

enum _Page { qualities, lines, devices }

/// "获取直链" and "投屏" (3.x `KnownRoomLinkDialog`, `LiveDlnaPage`;
/// docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一 c4, B-13): pick a quality, then a line, then (to
/// cast) a receiver; the header's ← goes back a page. The quality and line
/// that play are in the primary colour with a tick. One quality goes
/// straight to its lines, one line straight on (copied, or to the
/// receivers); an IPTV replay offers its replay address. Copying closes the
/// panel with "已复制直链".
class RoomStreamPanel extends StatefulWidget {
  /// Creates the panel.
  const new({required this.controller, required this.use, required this.onClose, this.dragToClose = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Copy or cast.
  final StreamUse use;

  /// Closes the panel.
  final VoidCallback onClose;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  @override
  State<RoomStreamPanel> createState() => _RoomStreamPanelState();
}

class _RoomStreamPanelState extends State<RoomStreamPanel> {
  final List<_Page> _pages = [_Page.qualities];
  int? _quality;
  List<String>? _urls;
  late int _line;
  String? _error;
  bool _busy = false;
  int _request = 0;

  /// An IPTV replay's address stands for every quality.
  late final bool _replay;

  LiveRoomController get _room => widget.controller;

  @override
  void initState() {
    super.initState();
    final replay = _room.room.catchUp.url?.trim() ?? '';
    _replay = replay.isNotEmpty;
    if (_replay) {
      _urls = [replay];
      _pages
        ..clear()
        ..add(_Page.lines);
    } else if (_room.qualities.length == 1) {
      unawaited(_resolve(0));
    }
  }

  Future<void> _resolve(int index) async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _quality = index;
    });
    String? error;
    List<String>? urls;
    try {
      final resolution = await _room.site.resolvePlayUrls(detail: _room.room, quality: _room.qualities[index]);
      if (resolution.inputRecipe != null) {
        // An owned source plays only inside the app (relay, session seat).
        error = i18n('toolbox_session_source');
      } else if (resolution.urls.isEmpty) {
        error = i18n('toolbox_get_url_failed');
      } else {
        urls = resolution.urls;
      }
    } on Object {
      error = i18n('toolbox_get_url_failed');
    }
    if (!mounted || request != _request) return;
    setState(() {
      _busy = false;
      _error = error;
      _urls = urls;
    });
    if (urls == null) return;
    if (urls.length == 1) {
      await _pick(0);
    } else {
      setState(() => _pages.add(_Page.lines));
    }
  }

  Future<void> _pick(int line) async {
    final url = _urls![line];
    switch (widget.use) {
      case StreamUse.copy:
        try {
          await Clipboard.setData(ClipboardData(text: url));
          AppNavigator.toast(i18n('toolbox_copy_success'));
        } on Object {
          AppNavigator.toast(i18n('toolbox_copy_failed'));
        }
        if (mounted) widget.onClose();
      case StreamUse.cast:
        setState(() {
          _line = line;
          _pages.add(_Page.devices);
        });
    }
  }

  void _back() {
    setState(() {
      _request++;
      _busy = false;
      _error = null;
      _pages.removeLast();
      if (_pages.last == _Page.qualities) _urls = null;
    });
  }

  /// Whether [index] is the quality that plays.
  bool _playingQuality(int? index) => !_replay && index == _room.qualityIndex;

  String get _qualityName => _quality == null ? '' : platformQualityName(_room.qualities[_quality!].quality);

  String _lineName(int index) => i18n('toolbox_line', args: {'index': '${index + 1}'});

  @override
  Widget build(BuildContext context) {
    final page = _pages.last;
    final title = i18n(widget.use == StreamUse.cast ? 'cast_screen' : 'toolbox_get_direct_link');
    return RoomSidePanel(
      key: ValueKey('stream-panel-${widget.use.name}'),
      title: title,
      onClose: widget.onClose,
      dragToClose: widget.dragToClose,
      leading: _pages.length > 1
          ? IconButton(
              key: const ValueKey('stream-panel-back'),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: _back,
              icon: const Icon(AppIcons.back),
            )
          : null,
      child: switch (page) {
        _Page.qualities => _qualities(context),
        _Page.lines => _lines(context),
        _Page.devices => CastDevices(
          key: ValueKey('cast-${_urls![_line]}'),
          url: _urls![_line],
          title: CastMedia.roomTitle(anchor: _room.room.nick, title: _room.room.title),
          caption: i18n('live_play_cast_to', args: {'source': _source(_line)}),
        ),
      },
    );
  }

  String _source(int line) {
    final parts = [
      if (!_replay && _qualityName.isNotEmpty) _qualityName,
      if ((_urls?.length ?? 0) > 1) _lineName(line),
    ];
    return parts.isEmpty ? _lineName(line) : parts.join(' · ');
  }

  Widget? _errorLine(BuildContext context) {
    final error = _error;
    if (error == null) return null;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(
        error,
        key: const ValueKey('stream-panel-error'),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.error),
      ),
    );
  }

  Widget _qualities(BuildContext context) {
    final qualities = _room.qualities;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (_busy) const LinearProgressIndicator(key: ValueKey('stream-panel-busy'), minHeight: 2),
        ?_errorLine(context),
        if (qualities.isEmpty)
          Padding(padding: const EdgeInsets.all(20), child: Text(i18n('toolbox_quality_failed')))
        else ...[
          PanelGroupTitle(i18n('toolbox_select_quality')),
          for (final (index, quality) in qualities.indexed)
            DialogOptionRow(
              key: ValueKey('stream-quality-$index'),
              label: platformQualityName(quality.quality),
              description: _playingQuality(index) ? i18n('now_playing') : null,
              selected: _playingQuality(index),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              trailing: _busy && _quality == index
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              enabled: !_busy,
              onTap: () => unawaited(_resolve(index)),
            ),
        ],
      ],
    );
  }

  Widget _lines(BuildContext context) {
    final urls = _urls ?? const <String>[];
    // The line that plays, when this is the quality that plays.
    final playing = _playingQuality(_quality) ? _room.session.state.lineIndex : null;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ?_errorLine(context),
        PanelGroupTitle(
          _replay || _qualityName.isEmpty
              ? i18n('toolbox_select_line')
              : i18n('live_play_stream_lines', args: {'quality': _qualityName}),
        ),
        for (final (index, url) in urls.indexed)
          DialogOptionRow(
            key: ValueKey('stream-line-$index'),
            label: _lineName(index),
            description: index == playing ? '${i18n('now_playing')} · $url' : url,
            descriptionMaxLines: 1,
            selected: index == playing,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            onTap: () => unawaited(_pick(index)),
          ),
      ],
    );
  }
}

/// Starts DLNA discovery (tests replace it).
@visibleForTesting
DlnaDiscoveryStarter castDiscovery = startDlnaDiscovery;

/// The DLNA receivers for [url] (3.x `LiveDlnaPage`): searches for 20 s,
/// lists the receivers and casts to the one tapped (a spinner while it
/// starts, then the primary colour with a tick); the logic is
/// `DlnaCastController` (M10). [caption] heads the list with the refresh on
/// its right. [title] is what the receiver shows; empty shows the address
/// (3.x).
class CastDevices extends StatefulWidget {
  /// Creates the list for [url].
  const new({required this.url, required this.caption, this.title = '', super.key});

  /// The stream address.
  final String url;

  /// Over the list ("原画 · 线路1 · 投屏到").
  final String caption;

  /// The title the receiver shows; empty shows [url].
  final String title;

  @override
  State<CastDevices> createState() => _CastDevicesState();
}

class _CastDevicesState extends State<CastDevices> {
  late final DlnaCastController _cast;
  late final StreamSubscription<DlnaCastState> _changes;
  final MulticastLock _lock = MulticastLock();

  @override
  void initState() {
    super.initState();
    _cast = DlnaCastController(
      widget.url,
      title: widget.title,
      startDiscovery: _discover,
      onNotice: (notice) => AppNavigator.toast(switch (notice) {
        DlnaCastNotice.castStarted => i18n('dlna_cast_started'),
        DlnaCastNotice.castFailed => i18n('dlna_cast_failed'),
      }),
    );
    _changes = _cast.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Many phones drop SSDP announcements without the multicast lock.
    unawaited(_lock.acquire());
    unawaited(_cast.startSearch());
  }

  /// Each search (the first and a refresh) asks for Android 17's
  /// local-network permission first; refused, the user is told and the
  /// search fails ("DLNA 设备搜索失败").
  Future<DlnaDiscoverySession> _discover() async {
    if (!await SystemAccess.requestLocalNetwork()) {
      AppNavigator.toast(i18n('local_network_denied_cast'));
      throw StateError('Local network access refused');
    }
    return await castDiscovery();
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    unawaited(_cast.close());
    unawaited(_lock.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = _cast.state;
    final message = switch (state.status) {
      DlnaCastStatus.searching => i18n('dlna_searching'),
      DlnaCastStatus.empty => i18n('dlan_device_not_found'),
      DlnaCastStatus.failed => i18n('dlna_search_failed'),
      DlnaCastStatus.invalidSource => i18n('dlna_invalid_source'),
      DlnaCastStatus.ready => null,
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SizedBox(
          height: 2,
          child: state.searching ? const LinearProgressIndicator(key: ValueKey('cast-searching'), minHeight: 2) : null,
        ),
        Row(
          children: [
            Expanded(child: PanelGroupTitle(widget.caption)),
            if (state.starting)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (state.status != DlnaCastStatus.invalidSource)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 4),
                child: IconButton(
                  key: const ValueKey('cast-refresh'),
                  tooltip: i18n('refresh'),
                  onPressed: state.busy ? null : () => unawaited(_cast.startSearch()),
                  icon: const Icon(AppIcons.refresh),
                ),
              ),
          ],
        ),
        if (state.error case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              i18n(switch (error) {
                DlnaCastError.searchInterrupted => 'dlna_search_interrupted',
                DlnaCastError.castFailed => 'dlna_cast_failed',
              }),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          ),
        for (final device in state.devices)
          DialogOptionRow(
            key: ValueKey('cast-device-${device.id}'),
            leading: Icon(AppIcons.castDevice, color: scheme.onSurfaceVariant),
            label: device.name.trim().isEmpty ? i18n('dlna_unknown_device') : device.name,
            description: device.address,
            descriptionMaxLines: 1,
            selected: state.selectedDeviceId == device.id && state.castingDeviceId != device.id,
            enabled: !state.busy,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            trailing: state.castingDeviceId == device.id
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: () => unawaited(_cast.castToDevice(device.id)),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              children: [
                Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 6),
                Text(
                  i18n('dlna_search_hint'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
