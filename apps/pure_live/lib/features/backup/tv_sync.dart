import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_net/live_net.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/qr_scan.dart';

/// The origin of a TV's sync server from what the user typed or a QR code
/// held: `http(s)://host[:port]` with nothing else (3.x
/// `normalizeScanSyncAddress`); a bare `host:port` gets `http://`. Null when
/// it is not one.
String? normalizeTvAddress(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.isEmpty || RegExp(r'[\u0000- \u007f]').hasMatch(value)) return null;
  if (!value.contains('://')) value = 'http://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.userInfo.isNotEmpty || (uri.path.isNotEmpty && uri.path != '/') || uri.hasQuery || uri.hasFragment) {
    return null;
  }
  return Uri(scheme: scheme, host: uri.host.toLowerCase(), port: uri.hasPort ? uri.port : null).toString();
}

/// The flat document 3.x sent to the TV (`exportToTVSettings`): the danmaku
/// settings, follows, block lists, history and the IPTV User-Agent, taken
/// from a full backup ([backup] in 3.x's sectioned layout). No accounts.
Map<String, Object?> tvSyncDocument(Map<String, Object?> backup) {
  Map<String, Object?> section(String name) => switch (backup[name]) {
    final Map<Object?, Object?> map => map.cast<String, Object?>(),
    _ => const {},
  };
  return {
    ...section('danmaku'),
    ...section('favorite'),
    ...section('history'),
    'customIptvUserAgent': section('iptv')['customIptvUserAgent'] ?? '',
  };
}

/// Sends [document] to the TV at [origin] (`POST /api/setSettings`, the
/// route pure_live_TV keeps for 3.x's phones). 3.x put the whole document in
/// the query string, which long follow and history lists push past URL
/// limits; the TV also reads `{"settings": …}` from the body, so it goes
/// there. True when the TV answered `data: true`.
Future<bool> sendToTv(LiveHttp http, String origin, Map<String, Object?> document) async {
  final response = await http.send(
    LiveRequest.json(site: 'tv-sync', url: Uri.parse('$origin/api/setSettings'), json: {'settings': document}),
  );
  if (!response.isSuccess) return false;
  try {
    final json = response.json;
    return json is Map && json['data'] == true;
  } on FormatException {
    return false;
  }
}

/// Asks for the TV's address (shown on the TV's sync screen); null when
/// cancelled. [scan] offers the camera inside the field (phones).
Future<String?> askTvAddress(BuildContext context, {bool scan = true}) => showAppDialog<String>(
  context: context,
  builder: (_) => _TvAddressDialog(scan: scan),
);

class _TvAddressDialog extends StatefulWidget {
  const new({required this.scan});

  final bool scan;

  @override
  State<_TvAddressDialog> createState() => _TvAddressDialogState();
}

class _TvAddressDialogState extends State<_TvAddressDialog> {
  final _address = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final origin = normalizeTvAddress(_address.text);
    if (origin == null) {
      setState(() => _error = i18n('remote_sync_invalid_address'));
      return;
    }
    Navigator.pop(context, origin);
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: i18n('sync_tv_data'),
    message: i18n('backup_tv_hint'),
    autofocus: false,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('backup-tv-address'),
          controller: _address,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: dialogFieldDecoration(
            context,
            label: i18n('remote_sync_address'),
            hint: i18n('remote_sync_input_address_hint'),
            error: _error,
            // The TV shows its address as a QR code (3.x scanned it).
            suffixIcon: !widget.scan
                ? null
                : qrScanButton(
                    context,
                    key: const ValueKey('backup-tv-scan'),
                    hint: i18n('scanner_sync_hint'),
                    onText: (text) {
                      _address.text = text;
                      _submit();
                    },
                  ),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      const DialogCancelButton(),
      DialogActionButton(key: const ValueKey('backup-tv-send'), label: i18n('remote_sync_send'), onPressed: _submit),
    ],
  );
}

enum _TvStage { scanning, sending, done, failed }

/// "同步TV数据" on phones (3.x `ScanCodePage`, docs/T09/T09c/T09c.2 c8):
/// scan the TV's code (or type its address), send, then say how it went:
/// "完成" / "再扫一次" after a success, the reason with "重试" / "输入地址"
/// after a failure. [send] sends this device's data to a TV origin.
class TvSyncScanPage extends StatefulWidget {
  /// Creates the page.
  const new({required this.send, super.key});

  /// Sends to the TV at an origin; true when the TV took it.
  final Future<bool> Function(String origin) send;

  @override
  State<TvSyncScanPage> createState() => _TvSyncScanPageState();
}

class _TvSyncScanPageState extends State<TvSyncScanPage> {
  _TvStage _stage = _TvStage.scanning;
  String? _origin;

  Future<void> _sendTo(String origin) async {
    setState(() {
      _origin = origin;
      _stage = _TvStage.sending;
    });
    final sent = await widget.send(origin);
    if (mounted) setState(() => _stage = sent ? _TvStage.done : _TvStage.failed);
  }

  void _scanned(String text) {
    final origin = normalizeTvAddress(text);
    if (origin == null) {
      setState(() {
        _origin = null;
        _stage = _TvStage.failed;
      });
      return;
    }
    unawaited(_sendTo(origin));
  }

  Future<void> _typeAddress() async {
    final origin = await askTvAddress(context, scan: false);
    if (origin != null && mounted) await _sendTo(origin);
  }

  void _scanAgain() => setState(() {
    _origin = null;
    _stage = _TvStage.scanning;
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final address = (_origin ?? '').replaceFirst(RegExp('^https?://'), '');
    final typeAddress = (
      label: i18n('qr_type_address'),
      icon: AppIcons.typeAddress as IconData?,
      onPressed: () => unawaited(_typeAddress()),
    );
    return QrScanPage(
      hint: i18n('scanner_sync_hint'),
      unavailableHint: i18n('qr_camera_unavailable_tv'),
      onCode: _scanned,
      onManual: () => unawaited(_typeAddress()),
      result: switch (_stage) {
        _TvStage.scanning => null,
        _TvStage.sending => QrScanStatus(
          key: const ValueKey('tv-sync-sending'),
          busy: true,
          title: i18n('syncing'),
          message: i18n('backup_tv_sending', args: {'address': address}),
        ),
        _TvStage.done => QrScanStatus(
          key: const ValueKey('tv-sync-done'),
          icon: AppIcons.syncDone,
          iconColor: LiveSemanticColors.success(Theme.of(context).brightness),
          title: i18n('sync_success'),
          message: i18n('backup_tv_sent'),
          primary: (label: i18n('done'), icon: null, onPressed: () => Navigator.of(context).pop()),
          secondary: (label: i18n('qr_scan_again'), icon: null, onPressed: _scanAgain),
        ),
        _TvStage.failed => QrScanStatus(
          key: const ValueKey('tv-sync-failed'),
          icon: AppIcons.syncFailed,
          iconColor: colors.error,
          title: i18n('sync_failed'),
          message: i18n(_origin == null ? 'remote_sync_invalid_address' : 'backup_tv_failed'),
          primary: (
            label: i18n('retry'),
            icon: null,
            onPressed: () => _origin == null ? _scanAgain() : unawaited(_sendTo(_origin!)),
          ),
          secondary: typeAddress,
        ),
      },
    );
  }
}
