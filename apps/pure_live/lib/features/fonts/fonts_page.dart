import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/fonts/fonts.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:url_launcher/url_launcher.dart';

/// 字体 (F-SET-01, F-DM-06): download fonts with a clear licence and use one
/// for the interface or for danmaku; the system font stays one tap away.
class FontsPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FontsPage> createState() => _FontsPageState();
}

class _FontsPageState extends ConsumerState<FontsPage> {
  final Map<String, double> _progress = {};
  final Set<String> _installed = {};
  bool _scanned = false;

  Future<void> _scan(List<FontEntry> fonts) async {
    final files = ref.read(fontFilesProvider);
    final installed = <String>{
      for (final font in fonts)
        if (await files.installed(font)) font.id,
    };
    if (!mounted) return;
    setState(() {
      _installed
        ..clear()
        ..addAll(installed);
      _scanned = true;
    });
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _download(FontEntry font) async {
    setState(() => _progress[font.id] = 0);
    try {
      await ref
          .read(fontFilesProvider)
          .download(font, progress: (value) => mounted ? setState(() => _progress[font.id] = value) : null);
      if (!mounted) return;
      setState(() => _installed.add(font.id));
      _say('“${font.name}”已下载');
    } on Object catch (error) {
      _say('$error');
    } finally {
      if (mounted) setState(() => _progress.remove(font.id));
    }
  }

  Future<void> _delete(FontEntry font) async {
    final settings = ref.read(storeProvider).settings;
    if (settings.get(Settings.appFontFamily) == font.id) await settings.set(Settings.appFontFamily, '');
    if (settings.get(Settings.danmakuFontFamily) == font.id) await settings.set(Settings.danmakuFontFamily, '');
    await ref.read(fontFilesProvider).delete(font);
    if (!mounted) return;
    setState(() => _installed.remove(font.id));
    _say('已删除“${font.name}”，重启后不再占用内存');
  }

  Future<void> _use(Setting<String> setting, FontEntry? font) async {
    final settings = ref.read(storeProvider).settings;
    await settings.set(setting, font?.id ?? '');
    if (font != null) await ref.read(fontFilesProvider).load(font);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(fontCatalogProvider);
    final settings = ref.watch(storeProvider).settings;
    final appFont = ref.watch(appFontFamilySetting);
    final danmakuFont = settings.get(Settings.danmakuFontFamily);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('字体')),
      body: catalogue.when(
        loading: () => const LoadingView(),
        error: (error, _) => const MessageView.error(title: '读不到字体列表'),
        data: (fonts) {
          if (!_scanned) unawaited(_scan(fonts));
          String nameOf(String id) =>
              id.isEmpty ? '系统字体' : fonts.where((font) => font.id == id).firstOrNull?.name ?? '系统字体';
          return ListView(
            children: [
              const SettingsHeader('正在使用'),
              ListTile(title: const Text('界面字体'), subtitle: Text(nameOf(appFont))),
              ListTile(title: const Text('弹幕字体'), subtitle: Text(nameOf(danmakuFont))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                child: Wrap(
                  spacing: Space.s2,
                  children: [
                    if (appFont.isNotEmpty)
                      TextButton(
                        onPressed: () => unawaited(_use(Settings.appFontFamily, null)),
                        child: const Text('界面改回系统字体'),
                      ),
                    if (danmakuFont.isNotEmpty)
                      TextButton(
                        onPressed: () => unawaited(_use(Settings.danmakuFontFamily, null)),
                        child: const Text('弹幕改回系统字体'),
                      ),
                  ],
                ),
              ),
              const SettingsHeader('可下载的字体'),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s2),
                child: Text(
                  '只列出允许自由使用和分发的字体（SIL OFL 1.1、IPA 字体许可）。字体文件较大，建议在 Wi-Fi 下下载。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              for (final font in fonts)
                _FontTile(
                  font: font,
                  installed: _installed.contains(font.id),
                  progress: _progress[font.id],
                  usedForApp: appFont == font.id,
                  usedForDanmaku: danmakuFont == font.id,
                  onDownload: () => unawaited(_download(font)),
                  onDelete: () => unawaited(_delete(font)),
                  onUseForApp: () => unawaited(_use(Settings.appFontFamily, font)),
                  onUseForDanmaku: () => unawaited(_use(Settings.danmakuFontFamily, font)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FontTile extends StatelessWidget {
  const new({
    required this.font,
    required this.installed,
    required this.progress,
    required this.usedForApp,
    required this.usedForDanmaku,
    required this.onDownload,
    required this.onDelete,
    required this.onUseForApp,
    required this.onUseForDanmaku,
  });

  final FontEntry font;
  final bool installed;
  final double? progress;
  final bool usedForApp;
  final bool usedForDanmaku;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onUseForApp;
  final VoidCallback onUseForDanmaku;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = [if (usedForApp) '界面', if (usedForDanmaku) '弹幕'];
    return ListTile(
      title: Text(
        font.name,
        // Installed fonts preview in their own face once registered.
        style: installed ? TextStyle(fontFamily: font.family) : null,
      ),
      subtitle: Text(
        [
          if (used.isNotEmpty) '用于${used.join('和')}',
          font.licenseName,
          if (font.description.isNotEmpty) font.description,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: switch (progress) {
        final value? => SizedBox.square(dimension: 24, child: CircularProgressIndicator(value: value, strokeWidth: 3)),
        null when !installed => IconButton(tooltip: '下载', icon: const Icon(Icons.download), onPressed: onDownload),
        null => PopupMenuButton<String>(
          tooltip: '使用',
          onSelected: (action) => switch (action) {
            'app' => onUseForApp(),
            'danmaku' => onUseForDanmaku(),
            _ => onDelete(),
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'app', child: Text('用作界面字体')),
            const PopupMenuItem(value: 'danmaku', child: Text('用作弹幕字体')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      },
      onTap: font.licenseUrl.isEmpty && font.official.isEmpty
          ? null
          : () => unawaited(
              launchUrl(
                Uri.parse(font.official.isNotEmpty ? font.official : font.licenseUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
    );
  }
}
