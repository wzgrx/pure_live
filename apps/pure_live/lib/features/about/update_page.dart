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
import 'package:pure_live_app/i18n/strings.g.dart';
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
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) _toast(t.common.couldNotOpenLink);
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast(message);
  }

  Future<void> _verify(Release release) async {
    final picked = await FilePicker.pickFiles(dialogTitle: t.about.pickInstaller);
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
          (final asset?, _) => t.about.verifyMatch(file: file.name, asset: asset.name),
          (null, final String _) => t.about.verifyMismatch(file: file.name),
          _ when release.assets.every((asset) => asset.sha256 == null) => t.about.verifyNoHashes(hash: hash),
          _ => t.about.verifyUnknown(file: file.name, hash: hash),
        };
      });
    } on FileSystemException catch (error) {
      setState(() => _verifyResult = t.about.readFileFailed(message: error.message));
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
      appBar: AppBar(title: Text(t.about.versionAndUpdates)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              if (checking) const LinearProgressIndicator(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(t.about.currentVersion(version: appVersion)),
                subtitle: Text(currentVersion.isPreRelease ? t.about.channelPreview : t.about.channelStable),
                trailing: TextButton(
                  onPressed: checking ? null : () => ref.read(updateProvider.notifier).check(),
                  child: Text(t.about.checkForUpdates),
                ),
              ),
              if (status?.error case final error?)
                ListTile(
                  leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
                  title: Text(updateErrorText(error)),
                  trailing: TextButton(
                    onPressed: () => _open(ref.read(updateCheckerProvider).releasesUrl),
                    child: Text(t.about.openReleasePage),
                  ),
                )
              else if (status != null && !status.checking && latest == null)
                ListTile(leading: const Icon(Icons.check_circle_outline), title: Text(t.about.upToDate)),
              if (latest != null) ..._latestSection(context, latest),
              if (status != null && status.releases.isNotEmpty) ...[
                const Divider(),
                ListTile(dense: true, title: Text(t.about.olderReleases)),
                for (final release in status.releases.where((release) => release != latest))
                  ExpansionTile(
                    title: Text(release.tag),
                    subtitle: Text(_describe(release)),
                    childrenPadding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(release.notes.trim().isEmpty ? t.about.noNotes : release.notes.trim()),
                      TextButton(onPressed: () => _open(release.pageUrl), child: Text(t.about.openReleasePage)),
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
    return [if (day.isNotEmpty) day, if (release.preRelease) t.about.preview].join(' · ');
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
        title: Text(t.about.newRelease(version: release.version), style: theme.textTheme.titleMedium),
        subtitle: Text(_describe(release)),
        trailing: TextButton(onPressed: () => _open(release.pageUrl), child: Text(t.about.releasePage)),
      ),
      if (recommended.isNotEmpty) ...[
        ListTile(dense: true, title: Text(t.about.recommendedDownloads)),
        for (final asset in recommended) _assetTile(asset, highlight: asset == recommended.first),
      ],
      if (others.isNotEmpty)
        ExpansionTile(title: Text(t.about.otherDownloads), children: [for (final asset in others) _assetTile(asset)]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _verifying ? null : () => _verify(release),
              icon: const Icon(Icons.verified_outlined),
              label: Text(_verifying ? t.about.calculating : t.about.verifyDownload),
            ),
            if (_verifyResult case final result?)
              Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Text(result),
              ),
            const SizedBox(height: Space.s2),
            Text(t.about.androidPreviewNote, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      ListTile(dense: true, title: Text(t.about.releaseNotes)),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
        child: SelectableText(release.notes.trim().isEmpty ? t.about.noNotes : release.notes.trim()),
      ),
    ];
  }

  Widget _assetTile(ReleaseAsset asset, {bool highlight = false}) {
    final label = switch (asset.kind) {
      AssetKind.androidApk => asset.abi == 'universal' ? t.about.androidUniversal : 'Android · ${asset.abi}',
      AssetKind.windowsSetup => t.about.windowsSetup,
      AssetKind.windowsPortable => t.about.windowsPortable,
      AssetKind.macos => 'macOS',
      AssetKind.linux => 'Linux',
      AssetKind.checksums => t.about.checksums,
      AssetKind.other => t.about.otherFile,
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
        tooltip: t.common.more,
        onSelected: (value) => switch (value) {
          'link' => _copy(asset.url.toString(), t.about.downloadLinkCopied),
          _ => _copy(sha!, t.about.hashCopied),
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'link', child: Text(t.about.copyDownloadLink)),
          if (sha != null) PopupMenuItem(value: 'sha', child: Text(t.about.copyHash)),
        ],
      ),
    );
  }
}
