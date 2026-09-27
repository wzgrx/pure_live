import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/appearance.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// Theme choice: system, light, dark, pure black.
class AppearancePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceProvider);
    const labels = {
      AppearanceMode.system: S.themeSystem,
      AppearanceMode.light: S.themeLight,
      AppearanceMode.dark: S.themeDark,
      AppearanceMode.black: S.themeBlack,
    };
    return Scaffold(
      appBar: AppBar(title: const Text(S.appearance)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
          child: RadioGroup<AppearanceMode>(
            groupValue: mode,
            onChanged: (value) => ref.read(appearanceProvider.notifier).set(value!),
            child: ListView(
              children: [
                for (final entry in labels.entries)
                  RadioListTile<AppearanceMode>(value: entry.key, title: Text(entry.value)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
