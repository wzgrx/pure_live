import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show PageMargin;
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/system_proxy.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// 设置 › 网络 (spec/product.md F-SET-07): one proxy for requests, chat,
/// playback and recording, optionally only for some platforms.
class NetworkSettings extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SystemProxyTile(),
      SwitchSettingTile(
        setting: Settings.proxyEnabled,
        title: t.settings.network.useProxy,
        subtitle: t.settings.network.useProxySubtitle,
      ),
      SettingBuilder<String>(
        setting: Settings.proxyHost,
        builder: (context, value, set) => ListTile(
          title: Text(t.settings.network.proxyHost),
          subtitle: Text(value.isEmpty ? t.settings.network.proxyHostUnset : value),
          onTap: () async {
            final text = await _editText(context, t.settings.network.proxyHost, value, TextInputType.url);
            if (text != null) set(text.trim());
          },
        ),
      ),
      SettingBuilder<int>(
        setting: Settings.proxyPort,
        builder: (context, value, set) => ListTile(
          title: Text(t.settings.network.proxyPort),
          subtitle: Text('$value'),
          onTap: () async {
            final text = await _editText(context, t.settings.network.proxyPort, '$value', TextInputType.number);
            final port = int.tryParse(text ?? '');
            if (port != null && port > 0 && port < 65536) set(port);
          },
        ),
      ),
      SettingsHeader(t.settings.network.proxyPlatforms),
      SettingBuilder<List<String>>(
        setting: Settings.proxyPlatforms,
        builder: (context, chosen, set) => Padding(
          padding: PageMargin.rowInsets(context).copyWith(top: 0, bottom: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chosen.isEmpty ? t.settings.network.proxyAll : t.settings.network.proxySelected,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in platformOrder)
                    FilterChip(
                      label: Text(platformNames[id] ?? id),
                      selected: chosen.contains(id),
                      onSelected: (on) => set(on ? [...chosen, id] : [...chosen.where((p) => p != id)]),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );

  static Future<String?> _editText(BuildContext context, String title, String initial, TextInputType type) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: type,
          inputFormatters: type == TextInputType.number ? [FilteringTextInputFormatter.digitsOnly] : null,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(t.common.save)),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

/// 跟随系统代理 (F-SET-07): shows what the system proxy is now.
class SystemProxyTile extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final system = ref.watch(systemProxyProvider);
    final manual = ref.watch(proxyEnabledSetting);
    return SwitchListTile(
      title: Text(t.settings.network.systemProxy),
      subtitle: Text(
        manual
            ? t.settings.network.systemProxyManual
            : system == null
            ? t.settings.network.systemProxyNone
            : t.settings.network.systemProxyIs(host: system.host, port: system.port),
      ),
      value: ref.watch(followSystemProxySetting),
      onChanged: (value) {
        unawaited(ref.read(followSystemProxySetting.notifier).set(value));
        unawaited(ref.read(systemProxyProvider.notifier).refresh());
      },
    );
  }
}
