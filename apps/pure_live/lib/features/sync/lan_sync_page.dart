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
    'android' => 'Android 设备',
    'windows' => 'Windows 电脑',
    'macos' => 'Mac',
    'ios' => 'iPhone / iPad',
    'linux' => 'Linux 电脑',
    _ => '纯粹直播',
  };
}

/// Chinese text for a send result.
String lanResultText(LanSendResult result) => switch (result) {
  LanSendResult.applied => '对方已确认并导入',
  LanSendResult.wrongCode => '配对码不对，请核对对方屏幕上的配对码（连续输错几次后对方会换一个新的）',
  LanSendResult.rejected => '对方拒绝了这次同步，或没有及时确认',
  LanSendResult.busy => '对方正在处理另一次同步，请稍后再试',
  LanSendResult.unsupported => '对方的版本不能接收 v4 的数据（3.x 只能接收 3.x 的数据），请改用备份文件或 WebDAV',
  LanSendResult.unreachable => '连不上对方：请确认两台设备在同一网络、对方已开始接收，地址和端口正确',
  LanSendResult.timeout => '等待对方确认超时',
  LanSendResult.failed => '对方导入失败',
};

const _localNetworkNote =
    'Android 17 起，系统可能要求允许“本地网络 / 附近的设备”权限；连不上时请到系统设置 › 应用 › 纯粹直播 › 权限中允许。\n'
    'Windows 第一次接收时会弹出防火墙提示，请允许在专用网络上访问。\n'
    '两台设备需要连在同一个 Wi-Fi（或同一局域网）下。';

/// 局域网同步 (F-SYNC-01, store.md §9): the receiver shows its address, a
/// pairing code and a QR code (3.x can scan it); the sender enters them. The
/// receiving user sees what would be imported and confirms before anything
/// is written. Accounts travel only inside a passphrase-encrypted section.
class LanSyncPage extends ConsumerStatefulWidget {
  const new({this.receive = false, super.key});

  /// Open on the receive tab and start receiving at once (first-run wizard).
  final bool receive;

  @override
  ConsumerState<LanSyncPage> createState() => _LanSyncPageState();
}

class _LanSyncPageState extends ConsumerState<LanSyncPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

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
      if (mounted) setState(() => _receiveError = '无法开始接收：$error');
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
    final from = sender == null ? incoming.remoteAddress : '${sender.name}（${incoming.remoteAddress}）';
    ref.read(appLogProvider).info('lan', 'package from ${incoming.remoteAddress}');
    try {
      final report = await confirmAndRestore(
        context,
        service: ref.read(backupServiceProvider),
        document: incoming.document,
        source: '来自 $from',
        title: '收到同步数据',
        showResult: false,
      );
      if (report == null) {
        _toast('已拒绝来自 $from 的数据');
        return LanDecision.rejected;
      }
      _toast('已导入来自 $from 的数据');
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
      setState(() => _sendResult = '请填写对方屏幕上显示的地址，例如 192.168.1.5:39888');
      return;
    }
    if (code.length != LanSyncProtocol.codeLength) {
      setState(() => _sendResult = '请填写对方屏幕上的 6 位配对码');
      return;
    }
    final options = await showExportOptions(context, title: '发送到对方', action: '发送');
    if (options == null || !mounted) return;
    setState(() {
      _sending = true;
      _sendResult = '正在等待对方确认…';
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
      if (mounted) setState(() => _sendResult = '发送失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('局域网同步'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: '接收'),
          Tab(text: '发送'),
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

  Widget _page(List<Widget> children) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
      child: ListView(padding: const EdgeInsets.all(Space.s4), children: children),
    ),
  );

  Iterable<Widget> _receiveTiles(BuildContext context) sync* {
    final theme = Theme.of(context);
    final receiver = _receiver;
    final port = _port;
    if (receiver == null || port == null) {
      yield const Text('在要接收数据的设备上开始接收，然后在另一台设备的“发送”里填写这里显示的地址和配对码。收到数据后会先让你确认，确认前不会写入任何内容。');
      yield const SizedBox(height: Space.s4);
      yield FilledButton.icon(
        onPressed: _starting ? null : _start,
        icon: const Icon(Icons.download_for_offline_outlined),
        label: Text(_starting ? '正在开始…' : '开始接收'),
      );
      if (_receiveError case final error?) {
        yield const SizedBox(height: Space.s3);
        yield Text(error, style: TextStyle(color: theme.colorScheme.error));
      }
    } else {
      final first = _addresses.firstOrNull;
      yield Text('正在接收', style: theme.textTheme.titleMedium);
      yield const SizedBox(height: Space.s2);
      if (_addresses.isEmpty) {
        yield const Text('没有找到本机的局域网地址，请先连接 Wi-Fi。');
      } else {
        yield Text('地址', style: theme.textTheme.labelLarge);
        for (final address in _addresses) {
          yield SelectableText('$address:$port', style: theme.textTheme.titleLarge);
        }
      }
      yield const SizedBox(height: Space.s3);
      yield Text('配对码', style: theme.textTheme.labelLarge);
      yield SelectableText(
        _code.length == 6 ? '${_code.substring(0, 3)} ${_code.substring(3)}' : _code,
        style: theme.textTheme.displaySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      );
      yield const Text('配对码只能用一次：收到一次数据或输错几次后会自动更换。');
      if (first != null) {
        final uri = LanSyncProtocol.qrUri(host: first, port: port, code: _code).toString();
        yield const SizedBox(height: Space.s4);
        yield Center(
          child: QrCodeView(data: uri, semanticLabel: '同步二维码'),
        );
        yield const SizedBox(height: Space.s2);
        yield const Center(child: Text('3.x 版本可以扫这个二维码发送数据'));
      }
      yield const SizedBox(height: Space.s4);
      yield OutlinedButton.icon(
        onPressed: _stop,
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('停止接收'),
      );
    }
    yield const SizedBox(height: Space.s6);
    yield Text(_localNetworkNote, style: theme.textTheme.bodySmall);
  }

  Iterable<Widget> _sendTiles(BuildContext context) sync* {
    final theme = Theme.of(context);
    yield const Text('先在另一台设备上打开“局域网同步 › 接收”，再填写它显示的地址和配对码。可以选择完整备份或仅关注；平台登录信息只有设置口令后才会加密发送。');
    yield const SizedBox(height: Space.s3);
    yield TextField(
      controller: _address,
      keyboardType: TextInputType.url,
      onChanged: _onAddressChanged,
      decoration: InputDecoration(
        labelText: '对方地址',
        hintText: '192.168.1.5:${LanSyncProtocol.port}',
        suffixIcon: IconButton(
          tooltip: '粘贴',
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
      decoration: const InputDecoration(labelText: '配对码', counterText: ''),
    );
    yield const SizedBox(height: Space.s4);
    yield FilledButton.icon(
      onPressed: _sending ? null : _send,
      icon: const Icon(Icons.send_outlined),
      label: Text(_sending ? '等待对方确认…' : '发送'),
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
