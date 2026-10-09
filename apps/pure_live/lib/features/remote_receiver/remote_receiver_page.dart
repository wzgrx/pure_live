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
import 'package:pure_live/shared/backup/backup_data.dart';
import 'package:pure_live/shared/backup/backup_preview_dialog.dart';
import 'package:pure_live/shared/backup/sync_parts.dart';
import 'package:pure_live/shared/qr_scan.dart';

/// Makes the page's sync service (tests replace it).
final Provider<RemoteSyncService Function()> remoteSyncServiceProvider = Provider<RemoteSyncService Function()>((ref) {
  final store = ref.watch(storeProvider);
  return () => RemoteSyncService(store);
});

/// The width from which the page lays out two columns (U.11c S2).
const double remoteSyncTwoColumns = 840;

/// Who another device is: its name and the line under it.
typedef _Peer = ({String name, String ip, int port, String detail});

/// One box of [_SyncPartsDialog]: the part and its words.
typedef _PartRow = ({SyncPart part, String text});

/// Device sync (3.x `lib/modules/remote_receiver`, docs/A-界面设计/A12-账号和数据界面/A12.6-设备同步).
///
/// Routes: `RoutePath.kRemoteSync`.
///
/// While the page is open this device serves its settings to devices that
/// know the pairing code (shown with the address and a QR code) and that the
/// user lets in; it can also send its settings to, or take them from,
/// another device found on the network or typed in (address or the QR
/// code's text). Taking settings shows what they change first.
class RemoteReceiverPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<RemoteReceiverPage> createState() => _RemoteReceiverPageState();
}

class _RemoteReceiverPageState extends ConsumerState<RemoteReceiverPage> {
  late final RemoteSyncService _service = ref.read(remoteSyncServiceProvider)()
    ..confirm = _confirmIncoming
    ..chooseImport = _chooseIncoming;
  final _address = TextEditingController();
  final _addressFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    unawaited(_service.start());
  }

  @override
  void dispose() {
    _service
      ..confirm = null
      ..chooseImport = null
      ..dispose();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  /// Another device asks to read or replace this device's settings; the
  /// page cannot be left until the user answers (3.x).
  Future<bool> _confirmIncoming(String action, String remoteAddress) async {
    if (!mounted) return false;
    final name = _service.nameOf(remoteAddress);
    final allowed = await showAppDialog<bool>(
      context: context,
      dismissible: false,
      builder: (dialogContext) => AppDialog(
        key: const ValueKey('remote-sync-incoming'),
        title: i18n('remote_sync'),
        message: i18n(
          switch ((action == 'import', name == null)) {
            (true, true) => 'remote_sync_incoming_import',
            (true, false) => 'remote_sync_incoming_import_named',
            (false, true) => 'remote_sync_incoming_export',
            (false, false) => 'remote_sync_incoming_export_named',
          },
          args: {'address': remoteAddress, 'name': name ?? ''},
        ),
        onEnter: () => Navigator.of(dialogContext).pop(true),
        actions: [
          DialogCancelButton(
            key: const ValueKey('remote-sync-reject'),
            label: i18n('remote_sync_reject'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          DialogActionButton(
            key: const ValueKey('remote-sync-allow'),
            label: i18n('remote_sync_allow'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    return allowed ?? false;
  }

  /// The code shown on [peer] before [action] ("发送", "接收"); null when
  /// cancelled or invalid.
  Future<String?> _askPairingCode(_Peer peer, {required String action}) async {
    final code = await showAppDialog<String>(
      context: context,
      builder: (_) => _PairingCodeDialog(name: peer.name, action: action),
    );
    if (code == null) return null;
    final normalized = RemoteSyncProtocol.normalizePairingCode(code);
    if (normalized.length != RemoteSyncProtocol.pairingCodeLength || int.tryParse(normalized) == null) {
      AppNavigator.toast(i18n('remote_sync_pairing_code_invalid'));
      return null;
    }
    return normalized;
  }

  /// Send: to whom and what goes, ticked (c3; J05.1), the code, then send.
  /// A device that cannot take parts on their own (3.x) gets everything:
  /// the boxes stay ticked and say why.
  Future<void> _send(_Peer peer, {String? code}) async {
    final partial = await _service.takesParts(peer.ip, peer.port);
    if (!mounted) return;
    final Map<SyncPart, int> counts;
    final Set<SyncPart> held;
    try {
      final outgoing = await _service.outgoing();
      counts = syncPartCounts(outgoing);
      held = syncPartsIn(outgoing).toSet();
    } on FormatException {
      AppNavigator.toast(i18n('remote_sync_send_failed'));
      return;
    }
    if (!mounted) return;
    final parts = await showAppDialog<Set<SyncPart>>(
      context: context,
      builder: (_) => _SyncPartsDialog(
        title: i18n('remote_sync_send'),
        message: i18n(
          partial ? 'remote_sync_parts_send_named' : 'remote_sync_confirm_send_named',
          args: {'name': peer.name},
        ),
        rows: [
          for (final MapEntry(key: part, value: count) in counts.entries)
            (part: part, text: i18n('remote_sync_part_count', args: {'part': i18n(part.labelKey), 'count': '$count'})),
        ],
        always: held.difference(counts.keys.toSet()),
        locked: !partial,
        note: partial ? null : i18n('remote_sync_parts_legacy'),
        confirmLabel: i18n('remote_sync_send_action'),
        confirmKey: const ValueKey('remote-sync-confirm'),
      ),
    );
    if (parts == null || !mounted) return;
    final pairing = code ?? await _askPairingCode(peer, action: i18n('remote_sync_send_action'));
    if (pairing == null) return;
    final ok = await _service.send(peer.ip, peer.port, pairing, parts: partial ? parts : null);
    AppNavigator.toast(i18n(ok ? 'remote_sync_send_success' : 'remote_sync_send_failed'));
  }

  /// Receive: the code, then what the other device's settings change, each
  /// part ticked, then apply the ticked ones (c2, S1; J05.1).
  Future<void> _receive(_Peer peer, {String? code}) async {
    final pairing = code ?? await _askPairingCode(peer, action: i18n('remote_sync_receive_action'));
    if (pairing == null || !mounted) return;
    final settings = await _service.fetch(peer.ip, peer.port, pairing);
    if (settings == null) {
      AppNavigator.toast(i18n('remote_sync_receive_failed'));
      return;
    }
    final RestorePreview preview;
    try {
      preview = await previewRestore(ref.read(storeProvider), settings, BackupScope.all);
    } on FormatException {
      AppNavigator.toast(i18n('remote_sync_receive_failed'));
      return;
    }
    if (!mounted) return;
    final styles = context.textStyles;
    final colors = Theme.of(context).colorScheme;
    final parts = await showAppDialog<Set<SyncPart>>(
      context: context,
      builder: (_) => _previewDialog(
        settings,
        preview,
        title: i18n('remote_sync_receive'),
        header: [
          Text(i18n('remote_sync_from', args: {'name': peer.name}), style: styles.t14SemiBold),
          const SizedBox(height: 2),
          Text(peer.detail, style: styles.t12.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 12),
        ],
        confirmLabel: i18n('remote_sync_receive_action'),
        confirmKey: const ValueKey('remote-sync-receive-confirm'),
      ),
    );
    if (parts == null || !mounted) return;
    final ok = await _service.apply(settings, parts: parts);
    AppNavigator.toast(i18n(ok ? 'remote_sync_receive_success' : 'remote_sync_receive_failed'));
  }

  /// Another device sends its settings: who, what they change, each part
  /// ticked; "拒绝" / "允许" and no closing outside (c8; J05.1). Null
  /// refuses them.
  Future<Set<SyncPart>?> _chooseIncoming(String remoteAddress, Map<String, Object?> settings) async {
    if (!mounted) return null;
    final RestorePreview preview;
    try {
      preview = await previewRestore(ref.read(storeProvider), settings, BackupScope.all);
    } on FormatException {
      return null;
    }
    if (!mounted) return null;
    final name = _service.nameOf(remoteAddress);
    return await showAppDialog<Set<SyncPart>>(
      context: context,
      dismissible: false,
      builder: (_) => _previewDialog(
        settings,
        preview,
        key: const ValueKey('remote-sync-incoming'),
        title: i18n('remote_sync'),
        message: i18n(
          name == null ? 'remote_sync_incoming_import' : 'remote_sync_incoming_import_named',
          args: {'address': remoteAddress, 'name': name ?? ''},
        ),
        header: const [],
        cancelLabel: i18n('remote_sync_reject'),
        cancelKey: const ValueKey('remote-sync-reject'),
        confirmLabel: i18n('remote_sync_allow'),
        confirmKey: const ValueKey('remote-sync-allow'),
      ),
    );
  }

  /// What [settings] change ([preview]), one ticked box per part they hold
  /// (the receive and the incoming send share it); the old flat file has no
  /// parts to pick and goes whole.
  Widget _previewDialog(
    Map<String, Object?> settings,
    RestorePreview preview, {
    required String title,
    required List<Widget> header,
    required String confirmLabel,
    required Key confirmKey,
    Key? key,
    String? message,
    String? cancelLabel,
    Key? cancelKey,
  }) {
    final splittable = syncPartsSplittable(settings);
    final held = splittable
        ? syncPartsIn(settings).toSet()
        : {
            SyncPart.settings,
            for (final part in preview.parts) ?SyncPart.of(part.kind),
            if (preview.accounts > 0) SyncPart.accounts,
          };
    final rows = <_PartRow>[
      if (preview.settingsInFile > 0 && held.contains(SyncPart.settings))
        (
          part: SyncPart.settings,
          text: i18n(
            'remote_sync_preview_settings',
            args: {'count': '${preview.settingsInFile}', 'changed': '${preview.settingsChanged}'},
          ),
        ),
      for (final part in preview.parts)
        if (SyncPart.of(part.kind) case final sync? when held.contains(sync)) (part: sync, text: restorePartText(part)),
      if (held.contains(SyncPart.accounts))
        (
          part: SyncPart.accounts,
          text: preview.accounts > 0
              ? i18n('backup_preview_accounts', args: {'count': '${preview.accounts}'})
              : i18n('remote_sync_preview_accounts_empty'),
        ),
    ];
    return _SyncPartsDialog(
      key: key,
      title: title,
      message: message,
      header: [
        ...header,
        Text(i18n('remote_sync_preview_title'), style: context.textStyles.t14SemiBold),
        const SizedBox(height: 4),
      ],
      rows: rows,
      always: held.difference({for (final row in rows) row.part}),
      lines: [if (!held.contains(SyncPart.accounts)) i18n('remote_sync_preview_no_accounts')],
      locked: !splittable,
      note: i18n('remote_sync_preview_warning'),
      contentKey: const ValueKey('remote-sync-preview'),
      cancelLabel: cancelLabel,
      cancelKey: cancelKey,
      confirmLabel: confirmLabel,
      confirmKey: confirmKey,
    );
  }

  _Peer _peerOf(RemoteSyncDevice device) => (
    name: device.name,
    ip: device.ip,
    port: device.port,
    detail: [
      device.address,
      // 3.x announces a fixed "1.0.0"; say which app it is instead.
      if (device.viaMdns) i18n('remote_sync_legacy_device') else if (device.version.isNotEmpty) 'v${device.version}',
    ].join(' · '),
  );

  /// A typed or scanned address: the device's name when it was heard.
  _Peer _peerAt(String ip, int port) {
    for (final device in _service.devices) {
      if (device.ip == ip && device.port == port) return _peerOf(device);
    }
    return (name: '$ip:$port', ip: ip, port: port, detail: '$ip:$port');
  }

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

  /// The bar's scan: the other device's code, then which way (3.x).
  Future<void> _scan() async {
    final text = await scanQrCode(
      context,
      hint: i18n('remote_sync_scan_other'),
      unavailableHint: i18n('remote_sync_camera_unavailable'),
      onManual: _addressFocus.requestFocus,
    );
    if (text == null || !mounted) return;
    final target = RemoteSyncProtocol.parseQr(text);
    if (target == null) {
      AppNavigator.toast(i18n('remote_sync_invalid_qr'));
      return;
    }
    final peer = _peerAt(target.ip, target.port);
    final send = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        key: const ValueKey('remote-sync-direction'),
        title: i18n('remote_sync_select_action'),
        message: peer.name == peer.detail ? peer.detail : '${peer.name} · ${target.ip}:${target.port}',
        actions: [
          TextButton(
            key: const ValueKey('remote-sync-direction-receive'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(i18n('remote_sync_receive')),
          ),
          DialogActionButton(
            key: const ValueKey('remote-sync-direction-send'),
            label: i18n('remote_sync_send'),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (send == null || !mounted) return;
    await (send ? _send(peer, code: target.code) : _receive(peer, code: target.code));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _service,
    builder: (context, _) => Scaffold(
      appBar: settingsPageAppBar(
        context,
        title: i18n('remote_sync'),
        actions: [
          if (QrScan.available)
            IconButton(
              key: const ValueKey('remote-sync-scan-bar'),
              tooltip: i18n('remote_sync_scan_qr'),
              onPressed: () => unawaited(_scan()),
              icon: const Icon(AppIcons.scanQr),
            ),
          IconButton(
            key: const ValueKey('remote-sync-toggle'),
            onPressed: _service.running ? _service.stop : _service.start,
            icon: Icon(_service.running ? AppIcons.syncStop : AppIcons.syncStart),
            tooltip: i18n(_service.running ? 'stop' : 'start'),
          ),
        ],
        bottom: _service.syncing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(key: ValueKey('remote-sync-progress'), minHeight: 2),
              )
            : null,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Two columns on wide windows; a phone held sideways (short)
          // keeps one (docs/specs/UI.md §5.1).
          final two =
              constraints.maxWidth >= remoteSyncTwoColumns &&
              constraints.maxHeight >= windowCompactHeight - kToolbarHeight;
          final note = Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              i18n('remote_sync_description'),
              style: context.textStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
          final local = _group(i18n('remote_sync_my_device'), _localDevice(), first: true);
          final others = [
            _group(i18n('remote_sync_devices'), _discovered(), first: two, trailing: _searching()),
            _group(i18n('remote_sync_manual'), _manual()),
          ];
          return SingleChildScrollView(
            physics: const PureLiveScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: two ? 1120 : readableContentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    note,
                    if (two)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: local),
                          const SizedBox(width: 32),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: others),
                          ),
                        ],
                      )
                    else ...[
                      local,
                      ...others,
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  /// A titled card (the settings groups' look; titles outside, c10).
  Widget _group(String title, Widget child, {bool first = false, Widget? trailing}) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, first ? 12 : 18, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: context.textStyles.t13.copyWith(fontWeight: FontWeight.w600, color: colors.primary),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget? _searching() {
    if (!_service.running) return null;
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('remote-sync-searching'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 6),
        Text(
          i18n('remote_sync_searching_short'),
          style: context.textStyles.t12.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _localDevice() {
    final colors = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final service = _service;
    final noAddress = service.address.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        children: [
          if (noAddress) ...[
            Container(
              key: const ValueKey('remote-sync-no-address'),
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: colors.surfaceContainerHigh, shape: BoxShape.circle),
              child: Icon(AppIcons.networkError, size: 48, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(i18n('remote_sync_no_address'), style: styles.t16.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              i18n('remote_sync_no_address_hint'),
              textAlign: TextAlign.center,
              style: styles.t13.copyWith(color: colors.onSurfaceVariant),
            ),
          ] else ...[
            if (service.qrData.isNotEmpty) QrCodeWidget(key: const ValueKey('remote-sync-qr'), data: service.qrData),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // One line: an address split mid-number misleads (A04.1);
                // large text shrinks it to fit instead.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SelectableText(
                      service.address,
                      key: const ValueKey('remote-sync-address'),
                      maxLines: 1,
                      style: styles.t18.copyWith(fontWeight: FontWeight.w600).tabular,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('remote-sync-copy'),
                  tooltip: i18n('remote_sync_copy_address'),
                  icon: const Icon(AppIcons.copy, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: service.address));
                    AppNavigator.toast(i18n('remote_sync_address_copied'));
                  },
                ),
              ],
            ),
            if (service.pairingCode.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(i18n('remote_sync_pairing_code'), style: styles.t12.copyWith(color: colors.onSurfaceVariant)),
              SelectableText(
                service.pairingCode,
                key: const ValueKey('remote-sync-code'),
                // 28 by default: the app bar title size × 28 / 20.
                style: styles.t20.emphasis
                    .copyWith(
                      fontSize: LiveFontSizes.of(Theme.of(context).textTheme).titleLarge * 28 / 20,
                      letterSpacing: 6,
                    )
                    .tabular,
              ),
              const SizedBox(height: 4),
              Text(i18n('remote_sync_scan_hint'), style: styles.t13.copyWith(color: colors.onSurfaceVariant)),
            ],
          ],
          const SizedBox(height: 8),
          SettingsSwitchRow(
            key: const ValueKey('remote-sync-accounts'),
            title: i18n('remote_sync_include_accounts'),
            subtitle: i18n('remote_sync_include_accounts_hint'),
            subtitleMaxLines: null,
            value: service.includeAccounts,
            onChanged: (value) => setState(() => service.includeAccounts = value),
          ),
          const SizedBox(height: 4),
          Row(
            key: const ValueKey('remote-sync-status'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                service.running ? AppIcons.syncRunning : AppIcons.syncNotRunning,
                size: 18,
                color: service.running ? colors.primary : colors.error,
              ),
              const SizedBox(width: 6),
              // Wraps instead of running off the card (A04.1: large text).
              Flexible(
                child: Text(
                  i18n(service.running ? 'remote_sync_running' : 'remote_sync_not_running'),
                  style: styles.t14.copyWith(color: service.running ? colors.onSurface : colors.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _discovered() {
    final devices = _service.devices;
    final colors = Theme.of(context).colorScheme;
    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Center(
          child: Text(
            i18n(_service.running ? 'remote_sync_searching' : 'remote_sync_no_devices'),
            key: const ValueKey('remote-sync-no-devices'),
            style: context.textStyles.t14.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final (index, device) in devices.indexed) ...[
          if (index > 0) Divider(height: 1, indent: 16, endIndent: 16, color: colors.outlineVariant),
          _device(device),
        ],
      ],
    );
  }

  Widget _device(RemoteSyncDevice device) {
    final colors = Theme.of(context).colorScheme;
    final peer = _peerOf(device);
    final icon = switch (device.platform) {
      'android' || 'ios' => AppIcons.devicePhone,
      'windows' || 'macos' || 'linux' => AppIcons.deviceComputer,
      _ => AppIcons.deviceOther,
    };
    return Padding(
      key: ValueKey('remote-sync-device-${device.id}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 24, color: colors.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name, style: context.textStyles.t15.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      peer.detail,
                      key: ValueKey('remote-sync-device-detail-${device.id}'),
                      style: context.textStyles.t12.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buttons(onReceive: () => unawaited(_receive(peer)), onSend: () => unawaited(_send(peer))),
        ],
      ),
    );
  }

  Widget _manual() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          i18n('remote_sync_manual_hint'),
          style: context.textStyles.t13.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('remote-sync-target'),
          controller: _address,
          focusNode: _addressFocus,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: '192.168.1.100:39888',
            prefixIcon: const Icon(AppIcons.lanAddress),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            // The other device's QR code carries its address and pairing
            // code (3.x scanned it).
            suffixIcon: qrScanButton(
              context,
              key: const ValueKey('remote-sync-scan'),
              hint: i18n('remote_sync_scan_other'),
              onText: (text) => _address.text = text,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buttons(
          onReceive: () {
            if (_typed() case final target?) unawaited(_receive(_peerAt(target.ip, target.port), code: target.code));
          },
          onSend: () {
            if (_typed() case final target?) unawaited(_send(_peerAt(target.ip, target.port), code: target.code));
          },
        ),
      ],
    ),
  );

  /// "接收配置" (outlined) then "发送配置" (filled), everywhere (c4).
  Widget _buttons({required VoidCallback onReceive, required VoidCallback onSend}) {
    final busy = _service.syncing;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('remote-sync-receive'),
            onPressed: busy ? null : onReceive,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(AppIcons.receive),
            label: Text(i18n('remote_sync_receive')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('remote-sync-send'),
            onPressed: busy ? null : onSend,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(AppIcons.send),
            label: Text(i18n('remote_sync_send')),
          ),
        ),
      ],
    );
  }
}

/// The pairing code of [name]: six boxes over one field (U.11c c3).
class _PairingCodeDialog extends StatefulWidget {
  const new({required this.name, required this.action});

  final String name;

  /// The main button: what the code is for (U.1d: the button says what
  /// happens).
  final String action;

  @override
  State<_PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<_PairingCodeDialog> {
  final _code = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const length = RemoteSyncProtocol.pairingCodeLength;
    return AppDialog(
      title: i18n('remote_sync_pairing_code'),
      message: i18n('remote_sync_pairing_code_for', args: {'name': widget.name}),
      autofocus: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Stack(
            children: [
              // Six boxes up to 44 wide, narrower on a narrow dialog.
              ValueListenableBuilder(
                valueListenable: _code,
                builder: (context, value, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < length; i++)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 44),
                            child: Container(
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: i == value.text.length ? colors.primary : colors.outline,
                                  width: i == value.text.length ? 2 : 1,
                                ),
                              ),
                              child: Text(
                                i < value.text.length ? value.text[i] : '',
                                style: context.textStyles.t20.copyWith(fontWeight: FontWeight.w600).tabular,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // The field takes the typing, the paste and the taps; the
              // boxes show it.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    key: const ValueKey('remote-sync-code-field'),
                    controller: _code,
                    focusNode: _focus,
                    autofocus: true,
                    showCursor: false,
                    keyboardType: TextInputType.number,
                    maxLength: length,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                    onSubmitted: (value) => Navigator.of(context).pop(value),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        const DialogCancelButton(),
        DialogActionButton(
          key: const ValueKey('remote-sync-code-ok'),
          label: widget.action,
          onPressed: () => Navigator.of(context).pop(_code.text),
        ),
      ],
    );
  }
}

/// The parts of a sync, one tick box each, all ticked to start with (the
/// whole sync, as before; docs/J-设置和数据/J05-设备同步/J05.1-同步前勾选内容):
/// "全选" above them when there are several; the main button needs one
/// ticked. [locked] keeps every box ticked (a 3.x device takes everything).
/// Closes with the ticked parts, or null.
class _SyncPartsDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.rows,
    required this.confirmLabel,
    required this.confirmKey,
    this.message,
    this.header = const [],
    this.lines = const [],
    this.always = const {},
    this.locked = false,
    this.note,
    this.contentKey,
    this.cancelLabel,
    this.cancelKey,
    super.key,
  });

  final String title;

  /// The text under the title.
  final String? message;

  /// Above the boxes.
  final List<Widget> header;

  final List<_PartRow> rows;

  /// Lines after the boxes that cannot be ticked.
  final List<String> lines;

  /// Parts the data holds without a box of their own (nothing to show for
  /// them): they go with the result when every box is ticked, so that sends
  /// or applies everything, as before.
  final Set<SyncPart> always;

  final bool locked;

  /// A small line at the bottom.
  final String? note;

  final Key? contentKey;
  final String confirmLabel;
  final Key confirmKey;
  final String? cancelLabel;
  final Key? cancelKey;

  @override
  State<_SyncPartsDialog> createState() => _SyncPartsDialogState();
}

class _SyncPartsDialogState extends State<_SyncPartsDialog> {
  // D08.1 c4: an opt-in part starts unticked (a locked dialog sends all).
  late final Set<SyncPart> _chosen = {
    for (final row in widget.rows)
      if (widget.locked || !row.part.optIn) row.part,
  };

  bool get _all => _chosen.length == widget.rows.length;

  void _set(SyncPart part, bool on) => setState(() => on ? _chosen.add(part) : _chosen.remove(part));

  /// The parts without a box go when every other box is ticked; an opt-in
  /// part left out does not hold them back.
  bool get _withAlways => widget.rows.every((row) => row.part.optIn || _chosen.contains(row.part));

  void _done() => Navigator.of(context).pop(<SyncPart>{..._chosen, if (_withAlways) ...widget.always});

  Widget _box({
    required Key key,
    required String text,
    required bool? value,
    required VoidCallback? onTap,
    bool tristate = false,
    TextStyle? style,
  }) => InkWell(
    key: key,
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
      child: Row(
        children: [
          Checkbox(
            value: value,
            tristate: tristate,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onTap == null ? null : (_) => onTap(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(text, style: style ?? context.textStyles.t14),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final styles = context.textStyles;
    final colors = Theme.of(context).colorScheme;
    final locked = widget.locked;
    final none = _chosen.isEmpty;
    return AppDialog(
      title: widget.title,
      message: widget.message,
      onEnter: none ? null : _done,
      content: Column(
        key: widget.contentKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...widget.header,
          if (widget.rows.length > 1 && !locked)
            _box(
              key: const ValueKey('remote-sync-part-all'),
              text: i18n('remote_sync_parts_all'),
              value: _all ? true : (none ? false : null),
              tristate: true,
              style: styles.t14SemiBold,
              onTap: () => setState(() {
                if (_all) {
                  _chosen.clear();
                } else {
                  _chosen.addAll([for (final row in widget.rows) row.part]);
                }
              }),
            ),
          for (final row in widget.rows)
            _box(
              key: ValueKey('remote-sync-part-${row.part.name}'),
              text: row.text,
              value: _chosen.contains(row.part),
              onTap: locked ? null : () => _set(row.part, !_chosen.contains(row.part)),
            ),
          for (final line in widget.lines)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
              child: Text(line, style: styles.t14.copyWith(color: colors.onSurfaceVariant)),
            ),
          if (widget.note case final note?) ...[
            const SizedBox(height: 8),
            Text(
              note,
              key: const ValueKey('remote-sync-parts-note'),
              style: styles.t12.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
      actions: [
        DialogCancelButton(
          key: widget.cancelKey,
          label: widget.cancelLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DialogActionButton(key: widget.confirmKey, label: widget.confirmLabel, onPressed: none ? null : _done),
      ],
    );
  }
}
