import 'package:flutter/material.dart';
import 'package:live_net/live_net.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

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
/// cancelled.
Future<String?> askTvAddress(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _TvAddressDialog());

class _TvAddressDialog extends StatefulWidget {
  const new();

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
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(i18n('sync_tv_data')),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n('backup_tv_hint'), style: context.textStyles.t13Muted),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('backup-tv-address'),
            controller: _address,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: i18n('remote_sync_address'),
              hintText: i18n('remote_sync_input_address_hint'),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
      FilledButton(key: const ValueKey('backup-tv-send'), onPressed: _submit, child: Text(i18n('remote_sync_send'))),
    ],
  );
}
