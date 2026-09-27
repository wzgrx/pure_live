import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pure_live_app/core/web/web_engine.dart';
import 'package:url_launcher/url_launcher.dart';

/// Microsoft's WebView2 download page (the Evergreen Bootstrapper is there).
final Uri webView2DownloadPage = Uri.parse('https://developer.microsoft.com/microsoft-edge/webview2/');

/// Checks the in-app browser before a page opens: true when it can open. On
/// Windows without the WebView2 Runtime it says how to install it
/// (spec/product.md F-SRC-02) and returns false.
Future<bool> ensureWebAvailable(BuildContext context, WidgetRef ref) async {
  final availability = await ref.read(webAvailabilityProvider.future);
  if (availability == WebAvailability.available) return true;
  if (availability == WebAvailability.missingRuntime && context.mounted) {
    await showDialog<void>(context: context, builder: (context) => const WebView2MissingDialog());
  }
  return false;
}

/// Explains the missing Microsoft Edge WebView2 Runtime and links to it.
class WebView2MissingDialog extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('需要 WebView2 运行时'),
    content: const SizedBox(
      width: 440,
      child: Text(
        '网页登录和网页搜索要用微软的 Microsoft Edge WebView2 运行时，这台电脑上没有找到它。Windows 11 和更新过的 Windows 10 一般已经自带。\n\n安装方法：打开微软的下载页，下载“常青版引导程序”（Evergreen Bootstrapper）并运行，装好后重新打开纯粹直播。',
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(
        onPressed: () async {
          Navigator.pop(context);
          await launchUrl(webView2DownloadPage, mode: LaunchMode.externalApplication);
        },
        child: const Text('打开下载页'),
      ),
    ],
  );
}
