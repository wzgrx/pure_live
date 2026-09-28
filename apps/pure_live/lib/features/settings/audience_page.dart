import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/audience.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// 观众数口径 (F-DSC-05): which figure cards show and what each platform's
/// figure means, so heat in the millions is not read as viewers.
class AudiencePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferOnline = ref.watch(preferRealOnlineSetting);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.settings.accounts.audience)),
      body: ListView(
        children: [
          SettingsHeader(t.settings.audience.shown),
          RadioGroup<bool>(
            groupValue: preferOnline,
            onChanged: (value) {
              if (value != null) unawaited(ref.read(preferRealOnlineSetting.notifier).set(value));
            },
            child: Column(
              children: [
                RadioListTile<bool>(
                  value: false,
                  title: Text(t.settings.audience.heatFirst),
                  subtitle: Text(t.settings.audience.heatFirstSubtitle),
                ),
                RadioListTile<bool>(
                  value: true,
                  title: Text(t.settings.audience.onlineFirst),
                  subtitle: Text(t.settings.audience.onlineFirstSubtitle),
                ),
              ],
            ),
          ),
          SettingsHeader(t.settings.audience.meaning),
          for (final id in platformOrder)
            if (audienceNotes[id] case final note?)
              ListTile(
                leading: PlatformLogo(platformId: id, size: Sizes.logoLarge),
                title: Text(platformNames[id] ?? id),
                subtitle: Text(note, style: theme.textTheme.bodySmall),
              ),
        ],
      ),
    );
  }
}
