import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/version.dart';
import 'package:pure_live_app/core/bytes.dart';
import 'package:pure_live_app/features/about/releases.dart';
import 'package:pure_live_app/features/about/update_state.dart';
import 'package:url_launcher/url_launcher.dart';

/// SHA-256 of a byte stream as lower-case hex.
Future<String> sha256Of(Stream<List<int>> bytes) async => (await sha256.bind(bytes).first).toString();

/// 版本与更新 (F-UPD-01, F-UPD-02): check GitHub for a newer v4 release, its
/// changelog, downloads for each platform and ABI with their SHA-256, and a
/// check of a downloaded file against it. Earlier v4 releases below.
class UpdatePage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends ConsumerState<UpdatePage> {
  String? _verifyResult;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    // Opening the page checks unless a check already ran in this session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(updateProvider) == null) unawaited(ref.read(updateProvider.notifier).check());
    });
  }

  void _toast(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) _toast('无法打开链接');
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast(message);
  }

  Future<void> _verify(Release release) async {
    final picked = await FilePicker.pickFiles(dialogTitle: '选择下载好的安装包');
    if (picked.isEmpty) return;
    final file = picked.single;
    setState(() {
      _verifying = true;
      _verifyResult = null;
    });
    try {
      final hash = await sha256Of(file.readAsByteStream());
      final match = release.assets.where((asset) => asset.sha256 == hash).firstOrNull;
      final expected = release.assets.where((asset) => asset.name == file.name).firstOrNull?.sha256;
      setState(() {
        _verifyResult = switch ((match, expected)) {
          (final asset?, _) => '校验通过：${file.name} 与 ${asset.name} 完全一致。',
          (null, final String _) => '校验失败：${file.name} 的 SHA-256 与发布页公布的不一致，请重新下载，不要安装。',
          _ when release.assets.every((asset) => asset.sha256 == null) => '这个版本没有公布 SHA-256，无法校验。文件的 SHA-256 是 $hash',
          _ => '没有找到对应的文件：${file.name} 的 SHA-256 是 $hash，与这个版本的任何文件都不一致。',
        };
      });
    } on FileSystemException catch (error) {
      setState(() => _verifyResult = '读取文件失败：${error.message}');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(updateProvider);
    final latest = status?.latest;
    final theme = Theme.of(context);
    final checking = status == null || status.checking;
    return Scaffold(
      appBar: AppBar(title: const Text('版本与更新')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              if (checking) const LinearProgressIndicator(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('当前版本 $appVersion'),
                subtitle: Text(currentVersion.isPreRelease ? '预览版：检查更新时也包含预览版' : '正式版：只检查正式版'),
                trailing: TextButton(
                  onPressed: checking ? null : () => ref.read(updateProvider.notifier).check(),
                  child: const Text('检查更新'),
                ),
              ),
              if (status?.error case final error?)
                ListTile(
                  leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
                  title: Text(updateErrorText(error)),
                  trailing: TextButton(
                    onPressed: () => _open(ref.read(updateCheckerProvider).releasesUrl),
                    child: const Text('打开发布页'),
                  ),
                )
              else if (status != null && !status.checking && latest == null)
                const ListTile(leading: Icon(Icons.check_circle_outline), title: Text('已是最新版本')),
              if (latest != null) ..._latestSection(context, latest),
              if (status != null && status.releases.isNotEmpty) ...[
                const Divider(),
                const ListTile(dense: true, title: Text('历史版本')),
                for (final release in status.releases.where((release) => release != latest))
                  ExpansionTile(
                    title: Text(release.tag),
                    subtitle: Text(_describe(release)),
                    childrenPadding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(release.notes.trim().isEmpty ? '（没有更新说明）' : release.notes.trim()),
                      TextButton(onPressed: () => _open(release.pageUrl), child: const Text('打开发布页')),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _describe(Release release) {
    final date = release.publishedAt?.toLocal();
    final day = date == null
        ? ''
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return [if (day.isNotEmpty) day, if (release.preRelease) '预览版'].join(' · ');
  }

  List<Widget> _latestSection(BuildContext context, Release release) {
    final theme = Theme.of(context);
    final recommended = recommendedAssets(release, platform: Platform.operatingSystem, abi: runningAndroidAbi());
    final others = release.assets
        .where((asset) => !recommended.contains(asset) && asset.kind != AssetKind.checksums)
        .toList();
    return [
      const Divider(),
      ListTile(
        leading: Icon(Icons.new_releases_outlined, color: theme.colorScheme.primary),
        title: Text('新版本 ${release.version}', style: theme.textTheme.titleMedium),
        subtitle: Text(_describe(release)),
        trailing: TextButton(onPressed: () => _open(release.pageUrl), child: const Text('发布页')),
      ),
      if (recommended.isNotEmpty) ...[
        const ListTile(dense: true, title: Text('适合本机的下载')),
        for (final asset in recommended) _assetTile(asset, highlight: asset == recommended.first),
      ],
      if (others.isNotEmpty)
        ExpansionTile(title: const Text('其它平台和文件'), children: [for (final asset in others) _assetTile(asset)]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _verifying ? null : () => _verify(release),
              icon: const Icon(Icons.verified_outlined),
              label: Text(_verifying ? '正在计算…' : '校验下载的文件'),
            ),
            if (_verifyResult case final result?)
              Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Text(result),
              ),
            const SizedBox(height: Space.s2),
            Text('Android 预览版的包名带 .next，可以和 3.x 同时安装；下载后在系统里打开安装包即可覆盖安装。', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      const ListTile(dense: true, title: Text('更新说明')),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
        child: SelectableText(release.notes.trim().isEmpty ? '（没有更新说明）' : release.notes.trim()),
      ),
    ];
  }

  Widget _assetTile(ReleaseAsset asset, {bool highlight = false}) {
    final label = switch (asset.kind) {
      AssetKind.androidApk => 'Android · ${asset.abi == 'universal' ? '通用' : asset.abi}',
      AssetKind.windowsSetup => 'Windows · 安装包',
      AssetKind.windowsPortable => 'Windows · 便携版',
      AssetKind.macos => 'macOS',
      AssetKind.linux => 'Linux',
      AssetKind.checksums => '校验值列表',
      AssetKind.other => '其它文件',
    };
    final sha = asset.sha256;
    return ListTile(
      leading: Icon(highlight ? Icons.download_for_offline : Icons.download_outlined),
      title: Text(asset.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          label,
          if (asset.size > 0) formatBytes(asset.size),
          if (sha != null) 'SHA-256 ${sha.substring(0, 16)}…',
        ].join(' · '),
      ),
      onTap: () => _open(asset.url),
      trailing: PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: (value) => switch (value) {
          'link' => _copy(asset.url.toString(), '下载链接已复制'),
          _ => _copy(sha!, 'SHA-256 已复制'),
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'link', child: Text('复制下载链接')),
          if (sha != null) const PopupMenuItem(value: 'sha', child: Text('复制 SHA-256')),
        ],
      ),
    );
  }
}
