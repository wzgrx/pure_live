import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/core/system_proxy.dart';

/// The user's proxy (spec/product.md F-SET-07) as live_net's per-site policy:
/// on with no platforms chosen → every platform; on with platforms → only
/// those; off → the system proxy when following it ([system]), else direct.
/// Adapters, chat, recording and playback all use it.
ProxyPolicy proxyPolicyFrom(SettingsStore settings, {SystemProxy? system}) {
  final host = settings.get(Settings.proxyHost).trim();
  if (!settings.get(Settings.proxyEnabled) || host.isEmpty) {
    final followed = _followed(settings, system);
    return followed == null ? const FixedProxyPolicy() : SystemProxyPolicy(followed);
  }
  final route = HttpProxyRoute(host, settings.get(Settings.proxyPort));
  final platforms = settings.get(Settings.proxyPlatforms);
  return platforms.isEmpty
      ? FixedProxyPolicy(global: route)
      : FixedProxyPolicy(perSite: {for (final platform in platforms) platform: route});
}

SystemProxy? _followed(SettingsStore settings, SystemProxy? system) =>
    settings.get(Settings.followSystemProxy) ? system : null;

/// `http://host:port` for mpv when [platform] goes through the proxy, else null.
String? mpvProxyFor(SettingsStore settings, String platform, {SystemProxy? system}) {
  final host = settings.get(Settings.proxyHost).trim();
  if (!settings.get(Settings.proxyEnabled) || host.isEmpty) return _followed(settings, system)?.url;
  final platforms = settings.get(Settings.proxyPlatforms);
  if (platforms.isNotEmpty && !platforms.contains(platform)) return null;
  return 'http://$host:${settings.get(Settings.proxyPort)}';
}

/// The current proxy policy; rebuilds when any proxy setting or the system
/// proxy changes.
final Provider<ProxyPolicy> proxyPolicyProvider = Provider<ProxyPolicy>((ref) {
  ref
    ..watch(proxyEnabledSetting)
    ..watch(proxyHostSetting)
    ..watch(proxyPortSetting)
    ..watch(proxyPlatformsSetting)
    ..watch(followSystemProxySetting);
  return proxyPolicyFrom(ref.read(storeProvider).settings, system: ref.watch(systemProxyProvider));
});

/// Follow the system proxy.
final followSystemProxySetting = NotifierProvider<SettingNotifier<bool>, bool>(
  () => SettingNotifier(Settings.followSystemProxy),
);

/// Proxy switch.
final proxyEnabledSetting = NotifierProvider<SettingNotifier<bool>, bool>(() => SettingNotifier(Settings.proxyEnabled));

/// Proxy host.
final proxyHostSetting = NotifierProvider<SettingNotifier<String>, String>(() => SettingNotifier(Settings.proxyHost));

/// Proxy port.
final proxyPortSetting = NotifierProvider<SettingNotifier<int>, int>(() => SettingNotifier(Settings.proxyPort));

/// Platforms that use the proxy.
final proxyPlatformsSetting = NotifierProvider<SettingNotifier<List<String>>, List<String>>(
  () => SettingNotifier(Settings.proxyPlatforms),
);

/// `http://host:port` of the proxy in force (manual, else the followed
/// system proxy), or null.
String? proxyUrl(SettingsStore settings, {SystemProxy? system}) {
  final host = settings.get(Settings.proxyHost).trim();
  if (!settings.get(Settings.proxyEnabled) || host.isEmpty) return _followed(settings, system)?.url;
  return 'http://$host:${settings.get(Settings.proxyPort)}';
}

/// CDN hosts whose media goes through the proxy. mpv only sees URLs, so the
/// app notes the hosts of a proxied platform's lines when it resolves them
/// (works for several platforms playing at once in multiview).
final class ProxiedHosts {
  /// The getter gives the system proxy at the time a room opens.
  new([this._system]);

  final SystemProxy? Function()? _system;
  final Set<String> _hosts = {};

  /// Notes [set]'s hosts when [platform] uses the proxy (bypassed system
  /// proxy hosts stay direct).
  void note(SettingsStore settings, String platform, StreamSet set) {
    final system = _system?.call();
    if (mpvProxyFor(settings, platform, system: system) == null) return;
    final manual = settings.get(Settings.proxyEnabled) && settings.get(Settings.proxyHost).trim().isNotEmpty;
    for (final line in set.lines) {
      if (!manual && system != null && system.bypasses(line.url.host)) continue;
      _hosts.add(line.url.host);
    }
  }

  /// Whether media from [uri] goes through the proxy.
  bool contains(Uri uri) => _hosts.contains(uri.host);
}

/// The app's proxied CDN hosts.
final Provider<ProxiedHosts> proxiedHostsProvider = Provider<ProxiedHosts>(
  (ref) => ProxiedHosts(() => ref.read(systemProxyProvider)),
);
