import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/secrets.dart';
import 'package:pure_live_app/core/sites.dart';

/// Platform accounts (principles §4.4 "平台与账号"): sign in by pasting the
/// site's cookie, sign out. Cookies are encrypted with the device key and are
/// not part of backups unless the user adds a passphrase (store.md §4, §7.3).
class AccountsPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  StreamSubscription<String>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = ref.read(secretStoreProvider).cookieChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _signIn(String platform) async {
    final controller = TextEditingController();
    final cookie = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('登录${platformNames[platform]}'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('在电脑浏览器登录该平台网页版后，从开发者工具里复制请求头中的 Cookie，粘贴到下面。'),
              const SizedBox(height: Space.s3),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(hintText: 'Cookie'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    if (cookie == null || cookie.isEmpty) return;
    await ref.read(secretStoreProvider).write(SecretRefs.cookie(platform), cookie);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，重新进入直播间后生效')));
  }

  Future<void> _signOut(String platform) async {
    await ref.read(secretStoreProvider).write(SecretRefs.cookie(platform), null);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已退出登录')));
  }

  @override
  Widget build(BuildContext context) {
    final secrets = ref.watch(secretStoreProvider);
    final platforms = ref.watch(enabledPlatformsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('平台账号')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              const Padding(padding: EdgeInsets.all(Space.s4), child: Text('登录信息用本机的系统密钥加密保存，不会上传，默认也不会写进备份文件。')),
              for (final platform in platforms)
                ListTile(
                  leading: PlatformLogo(platformId: platform, size: Sizes.iconLg),
                  title: Text(platformNames[platform] ?? platform),
                  subtitle: Text(secrets.cookieFor(platform) == null ? '未登录' : '已登录'),
                  trailing: secrets.cookieFor(platform) == null
                      ? FilledButton.tonal(onPressed: () => _signIn(platform), child: const Text('登录'))
                      : TextButton(onPressed: () => _signOut(platform), child: const Text('退出登录')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
