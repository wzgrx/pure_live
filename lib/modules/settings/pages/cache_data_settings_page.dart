import 'dart:async';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';

class CacheDataSettingsPage extends StatefulWidget {
  const CacheDataSettingsPage({super.key});

  @override
  State<CacheDataSettingsPage> createState() => _CacheDataSettingsPageState();
}

class _CacheDataSettingsPageState extends State<CacheDataSettingsPage> {
  @override
  void initState() {
    super.initState();
    unawaited(_refreshCacheSize(showFailure: false));
  }

  void _showCacheMessage(String message, {bool failed = false}) {
    if (!mounted) return;
    Get.snackbar(failed ? i18n('error') : i18n('done'), message, snackPosition: SnackPosition.bottom);
  }

  Future<void> _refreshThumbnails() async {
    try {
      await SettingsService.to.cache.refreshImageCache();
      _showCacheMessage(i18n('thumbnails_refreshed'));
    } catch (_) {
      _showCacheMessage(i18n('cache_operation_failed'), failed: true);
    }
  }

  Future<void> _refreshCacheSize({bool showFailure = true}) async {
    try {
      if (showFailure) {
        await SettingsService.to.cache.handleManualRefresh();
      } else {
        await SettingsService.to.cache.getCacheSize();
      }
    } catch (_) {
      if (showFailure) _showCacheMessage(i18n('cache_operation_failed'), failed: true);
    }
  }

  Future<void> _confirmClearCache(ThemeData theme) async {
    final pageContext = context;
    final ok = await showDialog<bool>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        title: Text(i18n('confirm_clear_local_cache')),
        content: Text(i18n('confirm_clear_local_cache_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(i18n('clear'), style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final result = await SettingsService.to.cache.clearCache();
      if (result.succeeded) {
        _showCacheMessage(i18n('cache_cleared'));
      } else {
        _showCacheMessage(
          i18n('cache_clear_incomplete', args: {'size': result.remainingSizeMB.toStringAsFixed(2)}),
          failed: true,
        );
      }
    } catch (_) {
      _showCacheMessage(i18n('cache_operation_failed'), failed: true);
    }
  }

  Widget _progressIndicator(Color color) =>
      SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(i18n("cache_and_data"))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n("cache_and_data")),
          context.buildModernCard([
            Obx(() {
              final size = SettingsService.to.cache.cacheSizeMB.value;
              final turns = SettingsService.to.cache.refreshTurns.value;
              final busy = SettingsService.to.cache.isBusy;
              return context.buildTile(
                icon: Remix.database_2_line,
                title: i18n("current_cache_size"),
                subtitle: "",
                onTap: busy ? null : _refreshCacheSize,
                stackTrailingOnNarrow: true,
                trailing: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "${size.toStringAsFixed(2)} MB",
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                    ),
                    if (SettingsService.to.cache.isScanning.value)
                      _progressIndicator(theme.colorScheme.primary)
                    else
                      AnimatedRotation(
                        turns: turns,
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeInOutCubic,
                        child: Icon(Remix.refresh_line, size: 16, color: theme.hintColor.withValues(alpha: 0.6)),
                      ),
                  ],
                ),
              );
            }),
            Obx(
              () => context.buildTile(
                icon: Remix.image_2_line,
                title: i18n('refresh_thumbnails'),
                subtitle: i18n('refresh_thumbnails_desc'),
                trailing: SettingsService.to.cache.isRefreshingImages.value
                    ? _progressIndicator(theme.colorScheme.primary)
                    : const Icon(Icons.refresh_rounded),
                onTap: SettingsService.to.cache.isBusy ? null : _refreshThumbnails,
              ),
            ),
            Obx(
              () => context.buildTile(
                icon: Remix.delete_bin_6_line,
                title: i18n('clear_local_cache'),
                subtitle: i18n('clear_local_cache_desc'),
                isLong: true,
                trailing: SettingsService.to.cache.isClearing.value
                    ? _progressIndicator(theme.colorScheme.error)
                    : Icon(Remix.delete_bin_6_line, color: theme.colorScheme.error),
                onTap: SettingsService.to.cache.isBusy ? null : () => _confirmClearCache(theme),
              ),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
