import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Theme mode, pure black and card density.
class AppearancePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeSetting);
    final labels = {
      AppThemeMode.system: t.app.themeSystem,
      AppThemeMode.light: t.app.themeLight,
      AppThemeMode.dark: t.app.themeDark,
    };
    return Scaffold(
      appBar: AppBar(title: Text(t.app.appearance)),
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
                title: Text(t.app.themeBlack),
                subtitle: Text(t.me.pureBlackSubtitle),
                value: ref.watch(pureBlackSetting),
                onChanged: (value) => ref.read(pureBlackSetting.notifier).set(value),
              ),
              SwitchListTile(
                title: Text(t.me.denseFollows),
                subtitle: Text(t.me.denseFollowsSubtitle),
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
