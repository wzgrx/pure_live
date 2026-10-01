import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_cast/live_cast.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/platform_services.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// What the stream picker does with the chosen address.
enum StreamUse {
  /// Copies it (3.x "get direct link").
  copy,

  /// Casts it to a DLNA receiver (3.x `castPlayUrlByRoomId`).
  cast,
}

/// Picks a quality and a line of the room's stream and copies or casts the
/// address (3.x `KnownRoomLinkDialog`). The playing quality is preselected;
/// an IPTV replay offers its replay address.
Future<void> showStreamPicker(BuildContext context, LiveRoomController controller, StreamUse use) async {
  final url = await showDialog<String>(
    context: context,
    builder: (_) => _StreamPickerDialog(controller: controller, use: use),
  );
  if (url == null || !context.mounted) return;
  switch (use) {
    case StreamUse.copy:
      try {
        await Clipboard.setData(ClipboardData(text: url));
        AppNavigator.toast(i18n('toolbox_copy_success'));
      } on Object {
        AppNavigator.toast(i18n('toolbox_copy_failed'));
      }
    case StreamUse.cast:
      await showCastDialog(context, url);
  }
}

class _StreamPickerDialog extends StatefulWidget {
  const new({required this.controller, required this.use});

  final LiveRoomController controller;
  final StreamUse use;

  @override
  State<_StreamPickerDialog> createState() => _StreamPickerDialogState();
}

class _StreamPickerDialogState extends State<_StreamPickerDialog> {
  List<String>? _urls;
  String? _error;
  bool _busy = false;
  int _request = 0;

  LiveRoomController get _room => widget.controller;

  @override
  void initState() {
    super.initState();
    final replay = _room.room.catchUp.url?.trim() ?? '';
    if (replay.isNotEmpty) {
      _urls = [replay];
    } else if (_room.qualities.length == 1) {
      unawaited(_resolve(_room.qualities.single));
    }
  }

  Future<void> _resolve(LivePlayQuality quality) async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    List<String>? urls;
    try {
      final resolution = await _room.site.resolvePlayUrls(detail: _room.room, quality: quality);
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
    if (urls != null && urls.length == 1) Navigator.of(context).pop(urls.single);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urls = _urls;
    final qualities = _room.qualities;
    final title = widget.use == StreamUse.cast ? i18n('cast_screen') : i18n('toolbox_get_direct_link');
    Widget body;
    if (_busy) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (urls != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(i18n('toolbox_select_line'), style: theme.textTheme.labelLarge),
          ),
          for (final (index, url) in urls.indexed)
            ListTile(
              key: ValueKey('stream-line-$index'),
              title: Text(i18n('toolbox_line', args: {'index': '${index + 1}'})),
              subtitle: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(context).pop(url),
            ),
        ],
      );
    } else if (qualities.isEmpty) {
      body = Padding(padding: const EdgeInsets.all(24), child: Text(i18n('toolbox_quality_failed')));
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(i18n('toolbox_select_quality'), style: theme.textTheme.labelLarge),
          ),
          for (final (index, quality) in qualities.indexed)
            ListTile(
              key: ValueKey('stream-quality-$index'),
              title: Text(quality.quality),
              trailing: index == _room.qualityIndex
                  ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                  : null,
              onTap: () => unawaited(_resolve(quality)),
            ),
        ],
      );
    }
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
                ),
              body,
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel')))],
    );
  }
}

/// Starts DLNA discovery (tests replace it).
@visibleForTesting
DlnaDiscoveryStarter castDiscovery = startDlnaDiscovery;

/// The DLNA dialog for [url] (3.x `LiveDlnaPage`): searches for 20 s,
/// lists the receivers and casts to the one tapped; the logic is
/// `DlnaCastController` (M10).
Future<void> showCastDialog(BuildContext context, String url) => showDialog<void>(
  context: context,
  builder: (_) => CastDialog(url: url),
);

/// The DLNA receivers and their state.
class CastDialog extends StatefulWidget {
  /// Creates the dialog for [url].
  const new({required this.url, super.key});

  /// The stream address.
  final String url;

  @override
  State<CastDialog> createState() => _CastDialogState();
}

class _CastDialogState extends State<CastDialog> {
  late final DlnaCastController _cast;
  late final StreamSubscription<DlnaCastState> _changes;
  final MulticastLock _lock = MulticastLock();

  @override
  void initState() {
    super.initState();
    _cast = DlnaCastController(
      widget.url,
      startDiscovery: castDiscovery,
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
    final state = _cast.state;
    final message = switch (state.status) {
      DlnaCastStatus.searching => i18n('dlna_searching'),
      DlnaCastStatus.empty => i18n('dlan_device_not_found'),
      DlnaCastStatus.failed => i18n('dlna_search_failed'),
      DlnaCastStatus.invalidSource => i18n('dlna_invalid_source'),
      DlnaCastStatus.ready => null,
    };
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(i18n('dlan_title'))),
          if (state.starting)
            const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else if (state.status != DlnaCastStatus.invalidSource)
            IconButton(
              key: const ValueKey('cast-refresh'),
              tooltip: i18n('refresh'),
              onPressed: state.busy ? null : () => unawaited(_cast.startSearch()),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      contentPadding: const EdgeInsets.only(top: 8, bottom: 8),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.searching) const LinearProgressIndicator(),
            if (state.error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  i18n(switch (error) {
                    DlnaCastError.searchInterrupted => 'dlna_search_interrupted',
                    DlnaCastError.castFailed => 'dlna_cast_failed',
                  }),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(
                      i18n('dlna_search_hint'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final device in state.devices)
                    ListTile(
                      key: ValueKey('cast-device-${device.id}'),
                      enabled: !state.busy,
                      leading: const Icon(Icons.tv_rounded),
                      title: Text(device.name.trim().isEmpty ? i18n('dlna_unknown_device') : device.name),
                      subtitle: Text(device.address),
                      trailing: state.castingDeviceId == device.id
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : state.selectedDeviceId == device.id
                          ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                          : null,
                      onTap: () => unawaited(_cast.castToDevice(device.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('close')))],
    );
  }
}
