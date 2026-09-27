import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

/// 设置 › 网络 (spec/product.md F-SET-07): one proxy for requests, chat,
/// playback and recording, optionally only for some platforms.
class NetworkSettings extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SwitchSettingTile(setting: Settings.proxyEnabled, title: '使用代理', subtitle: 'HTTP 代理，例如 Clash 的 7897 端口'),
      SettingBuilder<String>(
        setting: Settings.proxyHost,
        builder: (context, value, set) => ListTile(
          title: const Text('代理地址'),
          subtitle: Text(value.isEmpty ? '未设置（例如 127.0.0.1）' : value),
          onTap: () async {
            final text = await _editText(context, '代理地址', value, TextInputType.url);
            if (text != null) set(text.trim());
          },
        ),
      ),
      SettingBuilder<int>(
        setting: Settings.proxyPort,
        builder: (context, value, set) => ListTile(
          title: const Text('代理端口'),
          subtitle: Text('$value'),
          onTap: () async {
            final text = await _editText(context, '代理端口', '$value', TextInputType.number);
            final port = int.tryParse(text ?? '');
            if (port != null && port > 0 && port < 65536) set(port);
          },
        ),
      ),
      const SettingsHeader('走代理的平台'),
      SettingBuilder<List<String>>(
        setting: Settings.proxyPlatforms,
        builder: (context, chosen, set) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chosen.isEmpty ? '现在所有平台都走代理。选中下面的平台后，只有选中的平台走代理。' : '只有选中的平台走代理。',
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
