import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/bilibili_qr_login.dart';
import 'package:pure_live_app/features/sync/qr_code_view.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

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
      QrLoginPhase.loading => (t.accounts.qrLoading, false),
      QrLoginPhase.waiting => (t.accounts.qrWaiting, false),
      QrLoginPhase.scanned => (t.accounts.qrScanned, false),
      QrLoginPhase.expired => (t.accounts.qrExpired, true),
      QrLoginPhase.verifying => (t.accounts.verifyingSignIn, false),
      QrLoginPhase.done => (t.accounts.signedInName(name: _login.identity?.name ?? ''), false),
      QrLoginPhase.failed => (_login.message ?? t.accounts.signInFailed, true),
    };
    final showCode = code != null && (_login.phase == QrLoginPhase.waiting || _login.phase == QrLoginPhase.scanned);
    return Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 200,
            child: showCode
                ? QrCodeView(data: code.toString(), semanticLabel: t.accounts.qrLabel)
                : Center(
                    child: _login.phase == QrLoginPhase.loading || _login.phase == QrLoginPhase.verifying
                        ? const CircularProgressIndicator()
                        : LiveIcon(
                            _login.phase == QrLoginPhase.done ? LiveIcons.success : LiveIcons.qrCode,
                            size: Sizes.iconXxl,
                            color: theme.colorScheme.outline,
                          ),
                  ),
          ),
          const SizedBox(height: Space.s3),
          Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          if (refresh) ...[
            const SizedBox(height: Space.s2),
            FilledButton.tonal(onPressed: _login.start, child: Text(t.accounts.qrRefresh)),
          ],
        ],
      ),
    );
  }
}
