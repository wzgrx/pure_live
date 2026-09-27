import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// Theme mode, pure black and card density.
class AppearancePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeSetting);
    const labels = {
      AppThemeMode.system: S.themeSystem,
      AppThemeMode.light: S.themeLight,
      AppThemeMode.dark: S.themeDark,
    };
    return Scaffold(
      appBar: AppBar(title: const Text(S.appearance)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: ListView(
            children: [
              RadioGroup<AppThemeMode>(
                groupValue: mode,
                onChanged: (value) => ref.read(themeModeSetting.notifier).set(value!),
                child: Column(
                  children: [
                    for (final entry in labels.entries)
                      RadioListTile<AppThemeMode>(value: entry.key, title: Text(entry.value)),
                  ],
                ),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text(S.themeBlack),
                subtitle: const Text('深色时用纯黑背景，适合 OLED 屏幕'),
                value: ref.watch(pureBlackSetting),
                onChanged: (value) => ref.read(pureBlackSetting.notifier).set(value),
              ),
              SwitchListTile(
                title: const Text('关注页紧凑卡片'),
                subtitle: const Text('主播名和标题放在一行，一屏显示更多直播间'),
                value: ref.watch(denseFollowsSetting),
                onChanged: (value) => ref.read(denseFollowsSetting.notifier).set(value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
