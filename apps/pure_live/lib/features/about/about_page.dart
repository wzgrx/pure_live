import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/features/about/licenses.dart';
import 'package:pure_live_app/features/about/update_state.dart';
import 'package:pure_live_app/l10n/strings.dart';
import 'package:url_launcher/url_launcher.dart';

/// 关于 (F-UPD-03, principles §4.4): version and updates, project links,
/// licences (generated), privacy and trademark notes.
class AboutPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final latest = ref.watch(updateProvider)?.latest;
    final checker = ref.watch(updateCheckerProvider);
    Future<void> open(Uri url) async {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication) && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接')));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text(S.about)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.s6),
                child: Column(
                  children: [
                    Text(S.appName, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: Space.s1),
                    Text('Pure Live · ${S.version} $appVersion', style: theme.textTheme.bodyMedium),
                    if (currentVersion.isPreRelease) ...[
                      const SizedBox(height: Space.s2),
                      Text(S.previewNotice, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.system_update_outlined),
                title: const Text('版本与更新'),
                subtitle: Text(latest == null ? '查看更新说明、下载安装包' : '发现新版本 ${latest.version}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(updateLocation),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('项目主页'),
                subtitle: Text(checker.projectUrl.toString()),
                onTap: () => open(checker.projectUrl),
              ),
              ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('问题反馈'),
                subtitle: const Text('反馈问题时可以附上 设置 › 数据与同步 › 诊断与日志 里导出的诊断包'),
                onTap: () => open(checker.projectUrl.replace(path: '${checker.projectUrl.path}/issues')),
              ),
              ListTile(
                leading: const Icon(Icons.history_edu_outlined),
                title: const Text('发布记录'),
                onTap: () => open(checker.releasesUrl),
              ),
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: const Text('开源许可'),
                subtitle: const Text('本应用以 AGPL-3.0 发布；这里列出所用组件的许可证'),
                onTap: () {
                  registerAppLicenses();
                  showLicensePage(
                    context: context,
                    applicationName: S.appName,
                    applicationVersion: appVersion,
                    applicationLegalese: 'GNU AGPL-3.0-or-later',
                  );
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(Space.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('隐私', style: theme.textTheme.titleSmall),
                    const SizedBox(height: Space.s1),
                    Text(
                      '纯粹直播不收集、不上报任何数据。平台 Cookie 和密码加密保存在本机，默认不进入备份；局域网同步需要配对码并由接收方确认；崩溃报告默认关闭，打开后也只在本机提示导出诊断包。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: Space.s3),
                    Text('商标声明', style: theme.textTheme.titleSmall),
                    const SizedBox(height: Space.s1),
                    Text('各平台名称和标识归其所有者所有，仅用于标明内容来源。', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
