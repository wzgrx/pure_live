import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:pure_live_app/core/web/web_prompt.dart';
import 'package:pure_live_app/features/accounts/account_services.dart';
import 'package:pure_live_app/features/accounts/account_status.dart';
import 'package:pure_live_app/features/accounts/bilibili_qr_panel.dart';
import 'package:pure_live_app/features/accounts/cookie_editor.dart';
import 'package:pure_live_app/features/accounts/douyu_account.dart';
import 'package:pure_live_app/features/accounts/web_login.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

/// Location of one platform's account page.
String accountLocation(String platform) => '/me/accounts/${Uri.encodeComponent(platform)}';

/// Location of a platform's web sign-in (full screen, outside the shell).
String webLoginLocation(String platform) => '/web-login/${Uri.encodeComponent(platform)}';

/// Asks before signing out; true when the user confirmed.
Future<bool> confirmSignOut(BuildContext context, String platform, {required bool clearsBrowser}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('退出${platformNames[platform] ?? platform}账号？'),
        content: Text('会删除本机保存的登录信息${clearsBrowser ? '，并清除内置浏览器里的登录状态' : ''}。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
        ],
      ),
    ) ??
    false;

/// One platform's account (F-ACC-01): status, 校验, 退出 (confirmed), and the
/// ways to sign in: B 站 QR code and web page, Douyu's cookie with its
/// renewal keys, a pasted cookie everywhere.
class PlatformAccountPage extends ConsumerStatefulWidget {
  const new({required this.platform, super.key});

  /// Platform id.
  final String platform;

  @override
  ConsumerState<PlatformAccountPage> createState() => _PlatformAccountPageState();
}

class _PlatformAccountPageState extends ConsumerState<PlatformAccountPage> {
  bool _qr = false;
  bool _renewing = false;

  String get _platform => widget.platform;

  @override
  void initState() {
    super.initState();
    // The account's name comes from the platform; ask once on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final check = ref.read(accountCheckProvider(_platform));
      if (check is AccountUnchecked && ref.read(accountStoreProvider).cookie(_platform) != null) {
        unawaited(ref.read(accountCheckProvider(_platform).notifier).verify());
      }
    });
  }

  // A new message replaces the one on screen instead of queueing behind it.
  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _signOut() async {
    final engine = ref.read(webEngineProvider);
    final clearsBrowser = webLoginSpecs.containsKey(_platform) && engine != null;
    if (!await confirmSignOut(context, _platform, clearsBrowser: clearsBrowser)) return;
    await ref.read(accountStoreProvider).signOut(_platform);
    // spec/sites/bilibili.md §8.2: signing out also clears the browser's
    // cookies, so the web sign-in does not come back as the old account.
    if (clearsBrowser) {
      try {
        await engine.clearCookies();
      } on Object {
        // The stored cookie is gone either way.
      }
    }
    if (mounted) _toast('已退出登录');
  }

  Future<void> _renew() async {
    setState(() => _renewing = true);
    final message = await renewDouyuNow(
      ref.read(accountStoreProvider),
      ref.read(douyuRenewerProvider),
      now: DateTime.now(),
    );
    if (!mounted) return;
    setState(() => _renewing = false);
    _toast(message);
  }

  Future<void> _webLogin() async {
    if (!await ensureWebAvailable(context, ref) || !mounted) return;
    final done = await context.push<bool>(webLoginLocation(_platform));
    if (done ?? false) setState(() => _qr = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRevisionProvider);
    final store = ref.watch(accountStoreProvider);
    final check = ref.watch(accountCheckProvider(_platform));
    final signedIn = store.cookie(_platform) != null;
    final verifiable = ref.watch(accountVerifierProvider(_platform)) != null;
    final douyu = _platform == 'douyu' ? douyuStatus(store, DateTime.now()) : null;
    final web = webLoginSpecs.containsKey(_platform)
        ? ref.watch(webAvailabilityProvider).value ?? WebAvailability.unsupported
        : WebAvailability.unsupported;
    final name = platformNames[_platform] ?? _platform;
    return Scaffold(
      appBar: AppBar(title: Text('$name账号')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              ListTile(
                leading: PlatformLogo(platformId: _platform, size: Sizes.iconLg),
                title: Text(name),
                subtitle: Text(accountSummary(_platform, store, check, now: DateTime.now())),
              ),
              if (signedIn)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                  child: Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s2,
                    children: [
                      if (verifiable)
                        OutlinedButton(
                          onPressed: check is AccountChecking
                              ? null
                              : () => ref.read(accountCheckProvider(_platform).notifier).verify(),
                          child: const Text('校验'),
                        ),
                      if (douyu != null && douyu.renewable)
                        OutlinedButton(onPressed: _renewing ? null : _renew, child: const Text('立即续期')),
                      TextButton(onPressed: _signOut, child: const Text('退出登录')),
                    ],
                  ),
                ),
              if (_platform == 'bilibili') ...[
                SettingsHeader(signedIn ? '换个账号登录' : '登录'),
                if (_qr)
                  // Keyed: the list above it grows when the sign-in lands.
                  BilibiliQrPanel(key: const ValueKey('bilibili-qr'), onDone: () => _toast('已登录'))
                else
                  ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: const Text('扫码登录'),
                    subtitle: const Text('用哔哩哔哩手机客户端扫码'),
                    onTap: () => setState(() => _qr = true),
                  ),
                if (web != WebAvailability.unsupported)
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('网页登录'),
                    subtitle: const Text('在内置网页里用账号密码或短信登录'),
                    onTap: _webLogin,
                  ),
              ],
              SettingsHeader(_platform == 'bilibili' ? '手动填写 Cookie' : (signedIn ? '更换 Cookie' : '填写 Cookie')),
              CookieEditor(platform: _platform),
              const Padding(
                padding: EdgeInsets.all(Space.s4),
                child: Text('登录信息用本机的系统密钥加密保存，不会上传，界面和日志里都不显示；默认也不写进备份文件。'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
