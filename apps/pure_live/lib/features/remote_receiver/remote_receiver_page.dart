import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_protocol.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_service.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/qr_scan.dart';

/// Makes the page's sync service (tests replace it).
final Provider<RemoteSyncService Function()> remoteSyncServiceProvider = Provider<RemoteSyncService Function()>((ref) {
  final store = ref.watch(storeProvider);
  return () => RemoteSyncService(store);
});

/// Device sync (3.x `lib/modules/remote_receiver`).
///
/// Routes: `RoutePath.kRemoteSync`.
///
/// While the page is open this device serves its settings to devices that
/// know the pairing code (shown with the address and a QR code) and that the
/// user lets in; it can also send its settings to, or take them from,
/// another device found on the network or typed in (address or the QR
/// code's text).
class RemoteReceiverPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<RemoteReceiverPage> createState() => _RemoteReceiverPageState();
}

class _RemoteReceiverPageState extends ConsumerState<RemoteReceiverPage> {
  late final RemoteSyncService _service = ref.read(remoteSyncServiceProvider)()..confirm = _confirmIncoming;
  final _address = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_service.start());
  }

  @override
  void dispose() {
    _service
      ..confirm = null
      ..dispose();
    _address.dispose();
    super.dispose();
  }

  /// Another device asks to read or replace this device's settings.
  Future<bool> _confirmIncoming(String action, String remoteAddress) async {
    if (!mounted) return false;
    final allowed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('remote-sync-incoming'),
        title: Text(i18n('remote_sync')),
        content: Text(
          i18n(
            action == 'import' ? 'remote_sync_incoming_import' : 'remote_sync_incoming_export',
            args: {'address': remoteAddress},
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
          FilledButton(
            key: const ValueKey('remote-sync-allow'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(i18n('confirm')),
          ),
        ],
      ),
    );
    return allowed ?? false;
  }

  /// The code shown on the other device; null when cancelled or invalid.
  Future<String?> _askPairingCode() async {
    final controller = TextEditingController();
    try {
      final code = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(i18n('remote_sync_pairing_code')),
          content: TextField(
            key: const ValueKey('remote-sync-code-field'),
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: RemoteSyncProtocol.pairingCodeLength,
            decoration: InputDecoration(hintText: i18n('remote_sync_pairing_code_hint')),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(i18n('cancel'))),
            FilledButton(
              key: const ValueKey('remote-sync-code-ok'),
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(i18n('confirm')),
            ),
          ],
        ),
      );
      if (code == null) return null;
      final normalized = RemoteSyncProtocol.normalizePairingCode(code);
      if (normalized.length != RemoteSyncProtocol.pairingCodeLength || int.tryParse(normalized) == null) {
        AppNavigator.toast(i18n('remote_sync_pairing_code_invalid'));
        return null;
      }
      return normalized;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _send(String ip, int port, {String? code}) async {
    final confirmed = await _confirm(i18n('remote_sync_send'), i18n('remote_sync_confirm_send'));
    if (!confirmed || !mounted) return;
    final pairing = code ?? await _askPairingCode();
    if (pairing == null) return;
    final ok = await _service.send(ip, port, pairing);
    AppNavigator.toast(i18n(ok ? 'remote_sync_send_success' : 'remote_sync_send_failed'));
  }

  Future<void> _receive(String ip, int port, {String? code}) async {
    final confirmed = await _confirm(i18n('remote_sync_receive'), i18n('remote_sync_confirm_receive'));
    if (!confirmed || !mounted) return;
    final pairing = code ?? await _askPairingCode();
    if (pairing == null) return;
    final ok = await _service.receive(ip, port, pairing);
    AppNavigator.toast(i18n(ok ? 'remote_sync_receive_success' : 'remote_sync_receive_failed'));
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
            FilledButton(
              key: const ValueKey('remote-sync-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(i18n('confirm')),
            ),
          ],
        ),
      ) ??
      false;

  /// The typed target: an address, or the text of a sync QR code (which
  /// carries the pairing code).
  ({String ip, int port, String? code})? _typed() {
    final text = _address.text.trim();
    if (text.isEmpty) {
      AppNavigator.toast(i18n('remote_sync_enter_address'));
      return null;
    }
    final parsed = RemoteSyncProtocol.parseQr(text);
    if (parsed == null) AppNavigator.toast(i18n('remote_sync_invalid_address'));
    return parsed;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _service,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(i18n('remote_sync')),
        actions: [
          IconButton(
            key: const ValueKey('remote-sync-toggle'),
            onPressed: _service.running ? _service.stop : _service.start,
            icon: Icon(_service.running ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded),
            tooltip: i18n(_service.running ? 'stop' : 'start'),
          ),
          const SizedBox(width: 8),
        ],
        bottom: _service.syncing
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(i18n('remote_sync_description'), style: context.textStyles.t12Muted),
                  const SizedBox(height: 12),
                  _localDevice(),
                  const SizedBox(height: 16),
                  _discovered(),
                  const SizedBox(height: 16),
                  _manual(),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _localDevice() {
    final theme = Theme.of(context);
    final service = _service;
    return context.buildModernCard([
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(i18n('remote_sync_my_device'), style: context.textStyles.t16Bold),
            const SizedBox(height: 16),
            if (service.qrData.isNotEmpty)
              QrCodeWidget(key: const ValueKey('remote-sync-qr'), data: service.qrData)
            else
              SizedBox.square(
                dimension: 180,
                child: Icon(Icons.wifi_off_rounded, size: 56, color: theme.hintColor.withValues(alpha: 0.4)),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: SelectableText(
                    service.address.isEmpty ? i18n('remote_sync_no_address') : service.address,
                    key: const ValueKey('remote-sync-address'),
                    style: context.textStyles.t16Bold,
                  ),
                ),
                if (service.address.isNotEmpty)
                  IconButton(
                    tooltip: i18n('remote_sync_copy_address'),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: service.address));
                      AppNavigator.toast(i18n('remote_sync_address_copied'));
                    },
                  ),
              ],
            ),
            if (service.pairingCode.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(i18n('remote_sync_pairing_code'), style: context.textStyles.t12Muted),
              SelectableText(
                service.pairingCode,
                key: const ValueKey('remote-sync-code'),
                style: context.textStyles.t20.copyWith(fontWeight: FontWeight.bold, letterSpacing: 6),
              ),
            ],
            const SizedBox(height: 8),
            Text(i18n('remote_sync_scan_hint'), textAlign: TextAlign.center, style: context.textStyles.t12Muted),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('remote-sync-accounts'),
              contentPadding: EdgeInsets.zero,
              title: Text(i18n('remote_sync_include_accounts'), style: context.textStyles.t14),
              subtitle: Text(i18n('remote_sync_include_accounts_hint'), style: context.textStyles.t12Muted),
              value: service.includeAccounts,
              onChanged: (value) => setState(() => service.includeAccounts = value),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  service.running ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  size: 18,
                  color: service.running ? theme.colorScheme.primary : theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Text(i18n(service.running ? 'remote_sync_running' : 'remote_sync_not_running')),
              ],
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _discovered() {
    final devices = _service.devices;
    return context.buildModernCard([
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(i18n('remote_sync_devices'), style: context.textStyles.t16Bold)),
                if (_service.running)
                  const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    i18n(_service.running ? 'remote_sync_searching' : 'remote_sync_no_devices'),
                    style: context.textStyles.t13Muted,
                  ),
                ),
              )
            else
              for (final device in devices) _device(device),
          ],
        ),
      ),
    ]);
  }

  Widget _device(RemoteSyncDevice device) => Padding(
    key: ValueKey('remote-sync-device-${device.id}'),
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(device.platform == 'android' ? Icons.phone_android_rounded : Icons.computer_rounded),
          title: Text(device.name, style: context.textStyles.t14SemiBold),
          subtitle: Text(
            [
              device.address,
              // 3.x announces a fixed "1.0.0"; say which app it is instead.
              if (device.viaMdns)
                i18n('remote_sync_legacy_device')
              else if (device.version.isNotEmpty)
                'v${device.version}',
            ].join(' · '),
            key: ValueKey('remote-sync-device-detail-${device.id}'),
            style: context.textStyles.t12Muted,
          ),
        ),
        _buttons(
          onReceive: () => unawaited(_receive(device.ip, device.port)),
          onSend: () => unawaited(_send(device.ip, device.port)),
        ),
      ],
    ),
  );

  Widget _manual() => context.buildModernCard([
    Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n('remote_sync_manual'), style: context.textStyles.t16Bold),
          const SizedBox(height: 4),
          Text(i18n('remote_sync_manual_hint'), style: context.textStyles.t12Muted),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('remote-sync-target'),
            controller: _address,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: '192.168.1.100:39888',
              prefixIcon: const Icon(Icons.lan_outlined),
              border: const OutlineInputBorder(),
              // The other device's QR code carries its address and pairing
              // code (3.x scanned it).
              suffixIcon: qrScanButton(
                context,
                key: const ValueKey('remote-sync-scan'),
                onText: (text) => _address.text = text,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buttons(
            onReceive: () {
              if (_typed() case final target?) unawaited(_receive(target.ip, target.port, code: target.code));
            },
            onSend: () {
              if (_typed() case final target?) unawaited(_send(target.ip, target.port, code: target.code));
            },
          ),
        ],
      ),
    ),
  ]);

  Widget _buttons({required VoidCallback onReceive, required VoidCallback onSend}) {
    final busy = _service.syncing;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('remote-sync-receive'),
            onPressed: busy ? null : onReceive,
            icon: const Icon(Icons.download_rounded),
            label: Text(i18n('remote_sync_receive')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('remote-sync-send'),
            onPressed: busy ? null : onSend,
            icon: const Icon(Icons.upload_rounded),
            label: Text(i18n('remote_sync_send')),
          ),
        ),
      ],
    );
  }
}
