import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/bilibili_qr_login.dart';
import 'package:pure_live_app/features/sync/qr_code_view.dart';

/// B 站 QR sign-in in place (spec/sites/bilibili.md §8.3): the code, what
/// the phone did, and a refresh once it expired or failed. Polling stops
/// when the panel goes away.
class BilibiliQrPanel extends ConsumerStatefulWidget {
  const new({this.onDone, super.key});

  /// Called after the cookie was verified and stored.
  final VoidCallback? onDone;

  @override
  ConsumerState<BilibiliQrPanel> createState() => _BilibiliQrPanelState();
}

class _BilibiliQrPanelState extends ConsumerState<BilibiliQrPanel> {
  late final BilibiliQrLogin _login;

  @override
  void initState() {
    super.initState();
    final store = ref.read(accountStoreProvider);
    _login = BilibiliQrLogin(
      api: ref.read(bilibiliLoginProvider),
      save: (cookie, identity) => store.saveCookie('bilibili', cookie, uid: int.tryParse(identity.uid ?? '')),
    )..addListener(_changed);
    unawaited(_login.start());
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_login.phase == QrLoginPhase.done) widget.onDone?.call();
  }

  @override
  void dispose() {
    _login.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _login.code;
    final (text, refresh) = switch (_login.phase) {
      QrLoginPhase.loading => ('正在获取二维码', false),
      QrLoginPhase.waiting => ('用哔哩哔哩手机客户端扫描二维码', false),
      QrLoginPhase.scanned => ('已扫码，请在手机上确认登录', false),
      QrLoginPhase.expired => ('二维码已过期', true),
      QrLoginPhase.verifying => ('正在校验登录', false),
      QrLoginPhase.done => ('已登录：${_login.identity?.name ?? ''}', false),
      QrLoginPhase.failed => (_login.message ?? '登录失败', true),
    };
    final showCode = code != null && (_login.phase == QrLoginPhase.waiting || _login.phase == QrLoginPhase.scanned);
    return Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 200,
            child: showCode
                ? QrCodeView(data: code.toString(), semanticLabel: '哔哩哔哩登录二维码')
                : Center(
                    child: _login.phase == QrLoginPhase.loading || _login.phase == QrLoginPhase.verifying
                        ? const CircularProgressIndicator()
                        : Icon(
                            _login.phase == QrLoginPhase.done ? Icons.check_circle_outline : Icons.qr_code_2,
                            size: 64,
                            color: theme.colorScheme.outline,
                          ),
                  ),
          ),
          const SizedBox(height: Space.s3),
          Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          if (refresh) ...[
            const SizedBox(height: Space.s2),
            FilledButton.tonal(onPressed: _login.start, child: const Text('刷新二维码')),
          ],
        ],
      ),
    );
  }
}
