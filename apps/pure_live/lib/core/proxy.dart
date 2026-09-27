import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';

/// The user's proxy (spec/product.md F-SET-07) as live_net's per-site policy:
/// off → direct; on with no platforms chosen → every platform; otherwise only
/// the chosen platforms. Adapters, chat, recording and playback all use it.
ProxyPolicy proxyPolicyFrom(SettingsStore settings) {
  final host = settings.get(Settings.proxyHost).trim();
  if (!settings.get(Settings.proxyEnabled) || host.isEmpty) return const FixedProxyPolicy();
  final route = HttpProxyRoute(host, settings.get(Settings.proxyPort));
  final platforms = settings.get(Settings.proxyPlatforms);
  return platforms.isEmpty
      ? FixedProxyPolicy(global: route)
      : FixedProxyPolicy(perSite: {for (final platform in platforms) platform: route});
}

/// `host:port` for mpv when [platform] goes through the proxy, else null.
String? mpvProxyFor(SettingsStore settings, String platform) {
  final host = settings.get(Settings.proxyHost).trim();
  if (!settings.get(Settings.proxyEnabled) || host.isEmpty) return null;
  final platforms = settings.get(Settings.proxyPlatforms);
  if (platforms.isNotEmpty && !platforms.contains(platform)) return null;
  return 'http://$host:${settings.get(Settings.proxyPort)}';
}

/// The current proxy policy; rebuilds when any network.proxy* setting changes.
final Provider<ProxyPolicy> proxyPolicyProvider = Provider<ProxyPolicy>((ref) {
  ref
    ..watch(proxyEnabledSetting)
    ..watch(proxyHostSetting)
    ..watch(proxyPortSetting)
    ..watch(proxyPlatformsSetting);
  return proxyPolicyFrom(ref.read(storeProvider).settings);
});

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
