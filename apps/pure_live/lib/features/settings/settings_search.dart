import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/settings/settings_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// One setting the settings search can find (principles §4.4): its title
/// and description in the interface language, the section it sits in, and
/// the names 3.x gave it.
@immutable
final class SettingsEntry {
  const new({
    required this.id,
    required this.group,
    required this.title,
    this.subtitle,
    this.section,
    this.legacy = const [],
  });

  /// The [SettingAnchor] id of its tile: the setting's id, or a name for
  /// tiles that open a page.
  final String id;

  /// The group that shows it.
  final SettingsGroup group;

  /// Title.
  final String title;

  /// Description, if the tile has one.
  final String? subtitle;

  /// The heading above it in its group.
  final String? section;

  /// Names 3.x users know it by.
  final List<String> legacy;
}

/// An entry the query found, with the 3.x name that matched when only an
/// old name did.
typedef SettingsMatch = ({SettingsEntry entry, String? legacyName});

/// Every searchable setting of this device, in the order of the groups
/// (tiles shown only on other platforms are left out). Rebuilt on each
/// search, so it follows the interface language.
List<SettingsEntry> settingsIndex({bool? android, bool? windows}) {
  final isAndroid = android ?? Platform.isAndroid;
  final isWindows = windows ?? Platform.isWindows;
  final touch = isAndroid || (android == null && Platform.isIOS);
  final old = t.settings.search.legacy;
  final entries = <SettingsEntry>[];
  void add(SettingsGroup group, String id, String title, {String? subtitle, String? section, String? legacyKey}) {
    final names = old[legacyKey ?? id.replaceAll('.', '_')];
    entries.add(
      SettingsEntry(
        id: id,
        group: group,
        title: title,
        subtitle: subtitle,
        section: section,
        legacy: names == null ? const [] : names.split('|'),
      ),
    );
  }

  const general = SettingsGroup.general;
  final s = t.settings;
  add(general, Settings.locale.id, s.language);
  add(general, Settings.startPage.id, s.general.startPage);
  add(general, Settings.screenKeepOn.id, s.general.keepScreenOn);
  add(general, Settings.refreshRateMode.id, s.general.refreshRate);
  add(general, Settings.autoCheckUpdate.id, s.general.autoCheckUpdate);
  add(general, clipboardAnchor, t.backup.clipboardRooms, subtitle: t.backup.clipboardRoomsSubtitle);
  if (isWindows) {
    add(general, Settings.launchAtStartup.id, t.system.launchAtStartup, subtitle: t.system.launchAtStartupSubtitle);
    add(general, Settings.closeAction.id, t.system.onClose);
  }
  add(general, Settings.tvMode.id, s.general.tvMode, section: s.general.tv);
  add(
    general,
    Settings.tvPerformanceMode.id,
    s.general.tvFocusOutline,
    subtitle: s.general.tvFocusOutlineSubtitle,
    section: s.general.tv,
  );
  final refresh = s.general.followRefresh;
  add(general, Settings.autoRefreshFollows.id, s.general.autoRefreshFollows, section: refresh);
  add(general, Settings.refreshFollowsOnResume.id, s.general.refreshOnResume, section: refresh);
  add(general, Settings.autoRefreshInterval.id, s.general.refreshInterval, section: refresh);
  add(general, Settings.maxConcurrentRefresh.id, s.general.maxConcurrentRefresh, section: refresh);
  add(
    general,
    Settings.autoRefreshCovers.id,
    s.general.refreshCovers,
    subtitle: s.general.refreshCoversSubtitle,
    section: refresh,
  );
  add(general, Settings.coverRefreshInterval.id, s.general.coverInterval, section: refresh);
  add(
    general,
    Settings.liveAlerts.id,
    t.alerts.liveAlerts,
    subtitle: t.alerts.liveAlertsSubtitle,
    section: s.general.notifications,
  );

  const appearance = SettingsGroup.appearance;
  add(appearance, Settings.themeMode.id, s.appearance.theme);
  add(appearance, Settings.pureBlack.id, t.app.themeBlack, subtitle: t.me.pureBlackSubtitle);
  if (isWindows) {
    add(appearance, Settings.dynamicColor.id, s.appearance.accentColor, subtitle: s.appearance.accentColorSubtitle);
  } else if (isAndroid) {
    add(
      appearance,
      Settings.dynamicColor.id,
      s.appearance.wallpaperColor,
      subtitle: s.appearance.wallpaperColorSubtitle,
    );
  }
  add(appearance, Settings.denseFollows.id, t.me.denseFollows, subtitle: s.appearance.denseSubtitle);
  add(
    appearance,
    (touch ? Settings.cardPresetMobile : Settings.cardPresetDesktop).id,
    touch ? s.appearance.compactCardsPhone : s.appearance.compactCardsDesktop,
    subtitle: s.appearance.denseSubtitle,
    legacyKey: 'roomCard',
  );
  add(appearance, fontsAnchor, t.fonts.title, subtitle: s.appearance.fontsSubtitle, legacyKey: 'fonts');
  add(appearance, Settings.textScale.id, s.appearance.textSize);

  const playback = SettingsGroup.playback;
  final p = s.playback;
  final out = s.output;
  add(playback, Settings.qualityWifi.id, p.qualityWifi);
  add(playback, Settings.qualityMobile.id, p.qualityMobile);
  add(playback, Settings.autoLowerQuality.id, p.autoLower, subtitle: p.autoLowerSubtitle);
  add(playback, Settings.globalMute.id, out.startMuted, subtitle: out.startMutedSubtitle, section: out.volume);
  if (touch) {
    add(playback, Settings.defaultMobileVolume.id, out.defaultVolume, section: out.volume);
  } else {
    add(playback, Settings.defaultDesktopVolume.id, out.defaultVolumeDesktop, section: out.volume);
  }
  add(
    playback,
    Settings.hardwareDecoding.id,
    out.hardwareDecoding,
    subtitle: out.hardwareDecodingSubtitle,
    section: out.decoding,
  );
  add(playback, Settings.hardwareDecoder.id, out.decoder, section: out.decoding);
  if (isAndroid) {
    add(
      playback,
      Settings.androidCompatibility.id,
      out.compatibility,
      subtitle: out.compatibilitySubtitle,
      section: out.decoding,
    );
  }
  add(playback, Settings.lowLatency.id, out.lowLatency, subtitle: out.lowLatencySubtitle, section: out.decoding);
  add(playback, Settings.audioOutput.id, out.audio, section: out.decoding);
  add(playback, Settings.videoFit.id, t.room.aspect);
  add(playback, Settings.fullScreenDefault.id, p.autoFullscreen);
  add(playback, Settings.switchRoomGesture.id, p.swipeRooms, subtitle: p.swipeRoomsSubtitle);
  add(
    playback,
    Settings.portraitAdaptation.id,
    p.portraitAdaptation,
    subtitle: p.portraitAdaptationSubtitle,
    section: p.portrait,
  );
  add(playback, Settings.portraitFullscreenPolicy.id, p.fullscreenOrientation, section: p.portrait);
  add(playback, Settings.portraitFit.id, p.portraitFit, section: p.portrait);
  add(playback, Settings.portraitDanmakuArea.id, p.portraitDanmaku, section: p.portrait);
  add(
    playback,
    Settings.rememberPortraitOverride.id,
    p.rememberOrientation,
    subtitle: p.rememberOrientationSubtitle,
    section: p.portrait,
  );
  add(playback, Settings.backgroundPlay.id, p.background, subtitle: p.backgroundSubtitle, section: p.portrait);
  add(playback, Settings.asmrSleepMode.id, p.sleepMode, subtitle: p.sleepModeSubtitle, section: p.sleep);
  add(playback, Settings.asmrSleepMinutes.id, p.sleepMinutes, section: p.sleep);
  add(playback, Settings.miniPlayerOnLeave.id, t.system.miniOnLeave, subtitle: t.system.miniOnLeaveSubtitle);
  if (isAndroid) add(playback, Settings.autoPip.id, t.system.autoPip, subtitle: t.system.autoPipSubtitle);
  if (isWindows) add(playback, Settings.pipAlwaysOnTop.id, t.system.pipOnTop);
  if (!touch) add(playback, Settings.defaultMobileVolume.id, p.phoneVolume);

  const danmaku = SettingsGroup.danmaku;
  final d = t.danmaku;
  add(danmaku, Settings.danmakuEnabled.id, d.show, subtitle: d.showSubtitle);
  add(danmaku, Settings.danmakuFontSize.id, d.fontSize, section: d.style);
  add(danmaku, Settings.danmakuFontWeight.id, d.fontWeight, section: d.style);
  add(danmaku, Settings.danmakuOpacity.id, d.opacity, section: d.style);
  add(danmaku, Settings.danmakuSpeed.id, d.speedHint, section: d.style);
  add(danmaku, Settings.danmakuArea.id, d.area, section: d.style);
  add(danmaku, Settings.danmakuTopArea.id, d.topMargin, section: d.style);
  add(danmaku, Settings.danmakuBottomArea.id, d.bottomMargin, section: d.style);
  add(danmaku, Settings.danmakuStroke.id, d.stroke, section: d.style);
  add(danmaku, Settings.danmakuStrokeWidth.id, d.strokeWidth, section: d.style);
  add(danmaku, Settings.danmakuNoEmoji.id, d.hideEmoji, subtitle: d.hideEmojiSubtitle, section: d.style);
  add(danmaku, Settings.danmakuAutoFps.id, d.autoFps, subtitle: d.autoFpsSubtitle, section: d.style);
  add(danmaku, Settings.danmakuTapInteraction.id, d.tapDanmaku, subtitle: d.opensActions, section: d.videoTaps);
  add(
    danmaku,
    Settings.danmakuLongPressInteraction.id,
    d.longPressDanmaku,
    subtitle: d.opensActions,
    section: d.videoTaps,
  );
  add(danmaku, blockListAnchor, d.blockListTitle, section: d.filters);
  add(danmaku, Settings.danmakuCollapseRepeated.id, d.collapseRepeated, section: d.filters);
  add(
    danmaku,
    Settings.danmakuSimilarityFilter.id,
    d.filterSimilar,
    subtitle: d.filterSimilarSubtitle,
    section: d.filters,
  );
  add(danmaku, Settings.danmakuFilterDouyuAutomated.id, d.douyuBots, subtitle: d.douyuBotsSubtitle, section: d.filters);
  if (isAndroid || isWindows) {
    add(danmaku, Settings.danmakuPipEnabled.id, d.pipShow, section: d.pip);
    add(danmaku, Settings.danmakuPipFontSize.id, d.fontSize, section: d.pip);
    add(danmaku, Settings.danmakuPipSpeed.id, d.speed, section: d.pip);
    add(danmaku, Settings.danmakuPipOpacity.id, d.opacity, section: d.pip);
    add(danmaku, Settings.danmakuPipArea.id, d.area, section: d.pip);
    add(danmaku, Settings.danmakuPipMaxVisibleCount.id, d.maxOnScreen, section: d.pip);
    add(danmaku, Settings.danmakuPipNoEmoji.id, d.noEmoji, section: d.pip);
  }

  const recording = SettingsGroup.recording;
  final r = s.record;
  add(recording, recordCenterAnchor, t.app.recordings, subtitle: r.centerSubtitle);
  add(recording, Settings.recordDirectory.id, r.directory);
  add(recording, Settings.recordDefaultQuality.id, r.quality);
  add(recording, Settings.recordPolling.id, r.monitoring, subtitle: r.monitoringSubtitle, section: r.monitoring);
  add(recording, Settings.recordLiveCheckInterval.id, r.pollInterval, section: r.monitoring);
  add(recording, Settings.recordAutoReconnect.id, r.autoReconnect, section: r.reconnect);
  add(recording, Settings.recordMaxRetries.id, r.retries, section: r.reconnect);
  add(recording, Settings.recordRetryDelay.id, r.retryInterval, section: r.reconnect);
  add(recording, Settings.recordBackoff.id, r.backoff, subtitle: r.backoffSubtitle, section: r.reconnect);
  add(recording, Settings.recordMaxCheckInterval.id, r.maxBackoff, section: r.reconnect);
  add(recording, Settings.recordReadTimeout.id, r.readTimeout, section: r.reconnect);
  add(recording, Settings.recordMaxConcurrent.id, r.maxConcurrent, section: r.files);
  add(recording, Settings.recordSplitMinutes.id, r.splitDuration, section: r.files);
  add(recording, Settings.recordSplitMegabytes.id, r.splitSize, section: r.files);
  add(recording, Settings.recordDanmaku.id, r.saveDanmaku, subtitle: r.saveDanmakuSubtitle, section: r.files);
  add(recording, Settings.recordRemuxToMp4.id, r.remuxMp4, section: r.files);
  add(recording, Settings.recordKeepSourceAfterRemux.id, r.keepSource, section: r.files);
  add(recording, Settings.recordPinyinFolders.id, r.pinyinFolders, subtitle: r.pinyinFoldersSubtitle, section: r.files);
  add(recording, Settings.recordResumeOnLaunch.id, r.resumeOnStart, section: r.files);
  add(recording, Settings.recordCacheLimitEnabled.id, r.limitSize, subtitle: r.limitSizeSubtitle, section: r.space);
  add(recording, Settings.recordCacheLimitMb.id, r.sizeLimit, section: r.space);

  const accounts = SettingsGroup.accounts;
  add(accounts, platformsAnchor, s.accounts.platforms, subtitle: s.accounts.platformsSubtitle);
  add(accounts, audienceAnchor, s.accounts.audience, subtitle: s.accounts.audienceSubtitle);
  add(accounts, accountsAnchor, t.app.accounts, subtitle: s.accounts.accountsSubtitle);

  const network = SettingsGroup.network;
  final n = s.network;
  add(network, Settings.followSystemProxy.id, n.systemProxy);
  add(network, Settings.proxyEnabled.id, n.useProxy, subtitle: n.useProxySubtitle);
  add(network, Settings.proxyHost.id, n.proxyHost);
  add(network, Settings.proxyPort.id, n.proxyPort);
  add(network, Settings.proxyPlatforms.id, n.proxyPlatforms);

  const data = SettingsGroup.data;
  final b = t.backup;
  add(data, Settings.historyLimit.id, s.data.historyLimit);
  add(data, Settings.recordSearchHistory.id, s.data.searchHistory, subtitle: s.data.searchHistorySubtitle);
  add(data, backupAnchor, b.backupAndRestore, subtitle: b.backupAndRestoreSubtitle);
  add(data, webDavAnchor, 'WebDAV');
  add(data, lanSyncAnchor, b.lanSync);
  add(data, diagnosticsAnchor, b.diagnostics, subtitle: b.diagnosticsSubtitle);
  add(data, crashReportsAnchor, b.crashReports, subtitle: b.crashReportsSubtitle);
  add(data, cacheAnchor, t.health.clearImageCache);
  return entries;
}

/// Anchor ids of tiles that are not a single setting.
const clipboardAnchor = 'app.clipboardRecognition';

/// 字体.
const fontsAnchor = 'fonts';

/// 屏蔽词和屏蔽用户.
const blockListAnchor = 'danmaku.blockList';

/// 录制中心.
const recordCenterAnchor = 'record.center';

/// 首页平台.
const platformsAnchor = 'accounts.platforms';

/// 观众数口径.
const audienceAnchor = 'accounts.audience';

/// 平台账号.
const accountsAnchor = 'accounts.accounts';

/// 备份与恢复.
const backupAnchor = 'data.backup';

/// WebDAV.
const webDavAnchor = 'data.webdav';

/// 局域网同步.
const lanSyncAnchor = 'data.lan';

/// 诊断与日志.
const diagnosticsAnchor = 'data.diagnostics';

/// 崩溃报告.
const crashReportsAnchor = 'app.crashReports';

/// 清理图片缓存.
const cacheAnchor = 'data.cache';

String _fold(String text) => text.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// The entries of [index] that [query] finds, best first: title matches
/// (starting ones first), then 3.x names, then descriptions and sections.
/// Case and spaces do not matter.
List<SettingsMatch> searchSettings(String query, List<SettingsEntry> index) {
  final q = _fold(query);
  if (q.isEmpty) return const [];
  final ranked = <(int, int, SettingsMatch)>[];
  for (final (position, entry) in index.indexed) {
    final title = _fold(entry.title);
    final int rank;
    String? legacyName;
    if (title.startsWith(q)) {
      rank = 0;
    } else if (title.contains(q)) {
      rank = 1;
    } else if (entry.legacy.firstWhereOrNull((name) => _fold(name).contains(q)) case final name?) {
      rank = 2;
      legacyName = name;
    } else if (_fold(entry.subtitle ?? '').contains(q) || _fold(entry.section ?? '').contains(q)) {
      rank = 3;
    } else if (_fold(entry.group.label).contains(q)) {
      rank = 4;
    } else {
      continue;
    }
    ranked.add((rank, position, (entry: entry, legacyName: legacyName)));
  }
  ranked.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final (_, _, match) in ranked) match];
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}

/// A request to show one setting: the group page scrolls to it and lights
/// it up for a moment. A new request object repeats it for the same id.
final class SettingsSpotlightRequest {
  new(this.id);

  /// The anchor id.
  final String id;

  bool _claimed = false;

  /// True for the first anchor that asks: a setting shown twice lights once.
  bool claim() {
    if (_claimed) return false;
    return _claimed = true;
  }
}

/// Tells the [SettingAnchor]s below which setting to show.
class SettingsSpotlight extends InheritedWidget {
  const new({required this.request, required super.child, super.key});

  /// The setting to show, or null.
  final SettingsSpotlightRequest? request;

  /// The request above [context], if any.
  static SettingsSpotlightRequest? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsSpotlight>()?.request;

  @override
  bool updateShouldNotify(SettingsSpotlight oldWidget) => !identical(oldWidget.request, request);
}

/// Marks a settings tile for the settings search: when the spotlight names
/// [id], the tile scrolls into view and is lit up for two seconds.
class SettingAnchor extends StatefulWidget {
  const new({required this.id, required this.child, super.key});

  /// The setting's id (or a page tile's name, see [settingsIndex]).
  final String id;

  /// The tile.
  final Widget child;

  @override
  State<SettingAnchor> createState() => SettingAnchorState();
}

/// State of a [SettingAnchor]; public for tests.
class SettingAnchorState extends State<SettingAnchor> {
  SettingsSpotlightRequest? _handled;
  bool _lit = false;
  Timer? _timer;

  /// Whether the tile is lit up.
  bool get lit => _lit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final request = SettingsSpotlight.of(context);
    if (request == null || request.id != widget.id || identical(request, _handled)) return;
    _handled = request;
    if (!request.claim()) return;
    _lit = true;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.2,
        duration: still ? Duration.zero : Motion.long,
        curve: Curves.easeInOutCubic,
      );
    });
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _lit = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The selection tone of Material lists: marked, not shouting.
    final color = Theme.of(context).colorScheme.secondaryContainer;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // A Material of its own, so the tile's ink still shows over the light.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _lit ? color : color.withValues(alpha: 0)),
      duration: still ? Duration.zero : Motion.long,
      builder: (context, value, child) => Material(color: value, child: child),
      child: widget.child,
    );
  }
}

/// The search box at the top of the settings list (principles §4.4).
class SettingsSearchField extends StatelessWidget {
  const new({required this.controller, required this.onChanged, super.key});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(
      PageMargin.rowInsets(context).left,
      Space.s2,
      PageMargin.rowInsets(context).left,
      Space.s2,
    ),
    child: SearchBar(
      controller: controller,
      hintText: t.settings.search.hint,
      elevation: const WidgetStatePropertyAll(0),
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
      leading: const Icon(Icons.search),
      trailing: [
        if (controller.text.isNotEmpty)
          IconButton(
            tooltip: t.search.clear,
            icon: const Icon(Icons.close),
            onPressed: () {
              controller.clear();
              onChanged('');
            },
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

/// What the settings search found for [query]: each setting with where it
/// is, and the 3.x name when that is what matched.
class SettingsSearchResults extends StatelessWidget {
  const new({required this.query, required this.onOpen, super.key});

  final String query;

  /// Opens the group of an entry and shows the entry.
  final ValueChanged<SettingsEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final matches = searchSettings(query, settingsIndex());
    if (matches.isEmpty) {
      return ListTile(leading: const Icon(Icons.search_off), title: Text(t.settings.search.noResults));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (:entry, :legacyName) in matches)
          ListTile(
            leading: Icon(entry.group.icon),
            title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                [entry.group.label, ?entry.section].join(' › '),
                if (legacyName != null) t.settings.search.legacyName(name: legacyName),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onOpen(entry),
          ),
      ],
    );
  }
}
