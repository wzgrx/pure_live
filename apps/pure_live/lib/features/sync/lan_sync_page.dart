import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/backup/backup_flow.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/features/sync/lan_sync.dart';
import 'package:pure_live_app/features/sync/qr_code_view.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// HTTP for LAN sync: always direct, a proxy cannot reach the local network.
final lanHttpProvider = Provider<LiveHttp>((ref) {
  final http = IoLiveHttp(connectTimeout: const Duration(seconds: 5));
  ref.onDispose(http.close);
  return http;
});

/// This installation as a LAN sync device; the id is kept in the meta table
/// (store.md §9, 3.x `remote_sync_device_id`).
final lanDeviceProvider = FutureProvider<LanDevice>((ref) async {
  final meta = ref.watch(storeProvider).meta;
  var id = await meta.get(MetaStore.lanDeviceId);
  if (id == null || id.isEmpty) {
    final random = Random.secure();
    id = List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
    await meta.set(MetaStore.lanDeviceId, id);
  }
  return LanDevice(id: id, name: _deviceName(), platform: Platform.operatingSystem, version: appVersion);
});

String _deviceName() {
  String host;
  try {
    host = Platform.localHostname;
  } on Object {
    host = '';
  }
  if (host.isNotEmpty && host != 'localhost') return host;
  return switch (Platform.operatingSystem) {
    'android' => t.sync.device.android,
    'windows' => t.sync.device.windows,
    'macos' => 'Mac',
    'ios' => 'iPhone / iPad',
    'linux' => t.sync.device.linux,
    _ => t.app.name,
  };
}

/// Chinese text for a send result.
String lanResultText(LanSendResult result) => switch (result) {
  LanSendResult.applied => t.sync.lan.applied,
  LanSendResult.wrongCode => t.sync.lan.wrongCode,
  LanSendResult.rejected => t.sync.lan.rejected,
  LanSendResult.busy => t.sync.lan.busy,
  LanSendResult.unsupported => t.sync.lan.unsupported,
  LanSendResult.unreachable => t.sync.lan.unreachable,
  LanSendResult.timeout => t.sync.lan.timeout,
  LanSendResult.failed => t.sync.lan.failed,
};

String get _localNetworkNote => t.sync.lan.networkNote;

/// 局域网同步 (F-SYNC-01, store.md §9): the receiver shows its address, a
/// pairing code and a QR code (3.x can scan it); the sender enters them. The
/// receiving user sees what would be imported and confirms before anything
/// is written. Accounts travel only inside a passphrase-encrypted section.
class LanSyncPage extends ConsumerStatefulWidget {
  const new({this.receive = false, this.target, super.key});

  /// Open on the receive tab and start receiving at once (first-run wizard).
  final bool receive;

  /// An address to send to, from a scanned `purelive://host:port/sync?code=`
  /// link (F-SYNC-01): opens on the send tab with it filled in.
  final String? target;

  @override
  ConsumerState<LanSyncPage> createState() => _LanSyncPageState();
}

class _LanSyncPageState extends ConsumerState<LanSyncPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.target == null ? 0 : 1);

  // Receiving.
  LanSyncReceiver? _receiver;
  String _code = '';
  int? _port;
  List<String> _addresses = const [];
  bool _starting = false;
  String? _receiveError;

  // Sending.
  final _address = TextEditingController();
  final _pairing = TextEditingController();
  bool _sending = false;
  String? _sendResult;

  @override
  void initState() {
    super.initState();
    if (widget.receive) unawaited(_start());
    if (widget.target case final target?) {
      _address.text = target;
      _onAddressChanged(target);
    }
  }

  @override
  void dispose() {
    unawaited(_receiver?.stop());
    _tabs.dispose();
    _address.dispose();
    _pairing.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _start() async {
    if (_receiver != null || _starting) return;
    setState(() {
      _starting = true;
      _receiveError = null;
    });
    try {
      final device = await ref.read(lanDeviceProvider.future);
      final receiver = LanSyncReceiver(
        handler: _decide,
        device: device,
        onCodeChanged: (code) {
          if (mounted) setState(() => _code = code);
        },
      );
      final port = await receiver.start();
      final addresses = await localAddresses();
      if (!mounted) {
        await receiver.stop();
        return;
      }
      setState(() {
        _receiver = receiver;
        _code = receiver.code;
        _port = port;
        _addresses = addresses;
      });
      ref.read(appLogProvider).info('lan', 'receiving on port $port');
    } on Object catch (error) {
      ref.read(appLogProvider).warning('lan', 'receiver failed to start', error);
      if (mounted) setState(() => _receiveError = t.sync.lan.cannotReceive(error: error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    final receiver = _receiver;
    setState(() {
      _receiver = null;
      _port = null;
      _code = '';
    });
    await receiver?.stop();
  }

  Future<LanDecision> _decide(LanIncoming incoming) async {
    if (!mounted) return LanDecision.rejected;
    final sender = incoming.sender;
    final from = sender == null
        ? incoming.remoteAddress
        : t.sync.lan.senderWithAddress(name: sender.name, address: incoming.remoteAddress);
    ref.read(appLogProvider).info('lan', 'package from ${incoming.remoteAddress}');
    try {
      final report = await confirmAndRestore(
        context,
        service: ref.read(backupServiceProvider),
        document: incoming.document,
        source: t.sync.lan.from(from: from),
        title: t.sync.lan.received,
        showResult: false,
      );
      if (report == null) {
        _toast(t.sync.lan.declined(from: from));
        return LanDecision.rejected;
      }
      _toast(t.sync.lan.imported(from: from));
      return LanDecision.applied;
    } on FormatException catch (error) {
      _toast(backupErrorText(error));
      return LanDecision.invalid;
    } on BackupTooNewException catch (error) {
      _toast(backupErrorText(error));
      return LanDecision.invalid;
    } on Object catch (error, stack) {
      ref.read(appLogProvider).error('lan', 'import failed', error, stack);
      _toast(backupErrorText(error));
      return LanDecision.failed;
    }
  }

  void _onAddressChanged(String text) {
    final code = LanSyncProtocol.parseTarget(text)?.code;
    if (code != null && _pairing.text != code) _pairing.text = code;
  }

  Future<void> _send() async {
    final target = LanSyncProtocol.parseTarget(_address.text);
    final code = LanSyncProtocol.normalizeCode(_pairing.text);
    if (target == null) {
      setState(() => _sendResult = t.sync.lan.enterAddress);
      return;
    }
    if (code.length != LanSyncProtocol.codeLength) {
      setState(() => _sendResult = t.sync.lan.enterCode);
      return;
    }
    final options = await showExportOptions(context, title: t.sync.lan.sendTo, action: t.common.send);
    if (options == null || !mounted) return;
    setState(() {
      _sending = true;
      _sendResult = t.sync.lan.waiting;
    });
    try {
      final device = await ref.read(lanDeviceProvider.future);
      final document = await ref
          .read(backupServiceProvider)
          .export(scope: options.scope, passphrase: options.passphrase);
      final result = await LanSyncSender(ref.read(lanHttpProvider))
          .send(target, code, LanSyncProtocol.package(document, from: device));
      ref.read(appLogProvider).info('lan', 'sent to $target: ${result.name}');
      if (mounted) setState(() => _sendResult = lanResultText(result));
    } on Object catch (error, stack) {
      ref.read(appLogProvider).error('lan', 'send failed', error, stack);
      if (mounted) setState(() => _sendResult = t.sync.lan.sendFailed(error: error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageAppBar(
      maxContentWidth: Sizes.readingWidth,
      title: Text(t.backup.lanSync),
      bottom: TabBar(
        controller: _tabs,
        tabs: [
          Tab(text: t.sync.lan.receive),
          Tab(text: t.common.send),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      children: [
        _page([..._receiveTiles(context)]),
        _page([..._sendTiles(context)]),
      ],
    ),
  );

  Widget _page(List<Widget> children) => PageBody(
    maxContentWidth: Sizes.readingWidth,
    child: ListView(padding: const EdgeInsets.all(Space.s4), children: children),
  );

  Iterable<Widget> _receiveTiles(BuildContext context) sync* {
    final theme = Theme.of(context);
    final receiver = _receiver;
    final port = _port;
    if (receiver == null || port == null) {
      yield Text(t.sync.lan.receiveHint);
      yield const SizedBox(height: Space.s4);
      yield FilledButton.icon(
        onPressed: _starting ? null : _start,
        icon: const Icon(Icons.download_for_offline_outlined),
        label: Text(_starting ? t.sync.lan.starting : t.sync.lan.startReceiving),
      );
      if (_receiveError case final error?) {
        yield const SizedBox(height: Space.s3);
        yield Text(error, style: TextStyle(color: theme.colorScheme.error));
      }
    } else {
      final first = _addresses.firstOrNull;
      yield Text(t.sync.lan.receiving, style: theme.textTheme.titleMedium);
      yield const SizedBox(height: Space.s2);
      if (_addresses.isEmpty) {
        yield Text(t.sync.lan.noAddress);
      } else {
        yield Text(t.sync.lan.address, style: theme.textTheme.labelLarge);
        for (final address in _addresses) {
          yield SelectableText('$address:$port', style: theme.textTheme.titleLarge);
        }
      }
      yield const SizedBox(height: Space.s3);
      yield Text(t.sync.lan.code, style: theme.textTheme.labelLarge);
      yield SelectableText(
        _code.length == 6 ? '${_code.substring(0, 3)} ${_code.substring(3)}' : _code,
        style: theme.textTheme.displaySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      );
      yield Text(t.sync.lan.codeOnce);
      if (first != null) {
        final uri = LanSyncProtocol.qrUri(host: first, port: port, code: _code).toString();
        yield const SizedBox(height: Space.s4);
        yield Center(
          child: QrCodeView(data: uri, semanticLabel: t.sync.lan.qr),
        );
        yield const SizedBox(height: Space.s2);
        yield Center(child: Text(t.sync.lan.qrHint));
      }
      yield const SizedBox(height: Space.s4);
      yield OutlinedButton.icon(
        onPressed: _stop,
        icon: const Icon(Icons.stop_circle_outlined),
        label: Text(t.sync.lan.stopReceiving),
      );
    }
    yield const SizedBox(height: Space.s6);
    yield Text(_localNetworkNote, style: theme.textTheme.bodySmall);
  }

  Iterable<Widget> _sendTiles(BuildContext context) sync* {
    final theme = Theme.of(context);
    yield Text(t.sync.lan.sendHint);
    yield const SizedBox(height: Space.s3);
    yield TextField(
      controller: _address,
      keyboardType: TextInputType.url,
      onChanged: _onAddressChanged,
      decoration: InputDecoration(
        labelText: t.sync.lan.otherAddress,
        hintText: '192.168.1.5:${LanSyncProtocol.port}',
        suffixIcon: IconButton(
          tooltip: t.common.paste,
          icon: const Icon(Icons.content_paste),
          onPressed: () async {
            final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
            if (text == null) return;
            _address.text = text.trim();
            _onAddressChanged(_address.text);
          },
        ),
      ),
    );
    yield TextField(
      controller: _pairing,
      keyboardType: TextInputType.number,
      maxLength: 7,
      decoration: InputDecoration(labelText: t.sync.lan.code, counterText: ''),
    );
    yield const SizedBox(height: Space.s4);
    yield FilledButton.icon(
      onPressed: _sending ? null : _send,
      icon: const Icon(Icons.send_outlined),
      label: Text(_sending ? t.sync.lan.awaiting : t.common.send),
    );
    if (_sending) {
      yield const Padding(
        padding: EdgeInsets.only(top: Space.s3),
        child: LinearProgressIndicator(),
      );
    }
    if (_sendResult case final result?) {
      yield const SizedBox(height: Space.s3);
      yield Text(result);
    }
    yield const SizedBox(height: Space.s6);
    yield Text(_localNetworkNote, style: theme.textTheme.bodySmall);
  }
}
