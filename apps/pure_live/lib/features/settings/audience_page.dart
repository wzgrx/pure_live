import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/audience.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

/// 观众数口径 (F-DSC-05): which figure cards show and what each platform's
/// figure means, so heat in the millions is not read as viewers.
class AudiencePage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferOnline = ref.watch(preferRealOnlineSetting);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('观众数口径')),
      body: ListView(
        children: [
          const SettingsHeader('卡片显示'),
          RadioGroup<bool>(
            groupValue: preferOnline,
            onChanged: (value) {
              if (value != null) unawaited(ref.read(preferRealOnlineSetting.notifier).set(value));
            },
            child: const Column(
              children: [
                RadioListTile<bool>(
                  value: false,
                  title: Text('平台热度优先'),
                  subtitle: Text('显示各平台公开的热度或累计观看，这些数字不等于同时在线人数'),
                ),
                RadioListTile<bool>(value: true, title: Text('在线人数优先'), subtitle: Text('平台给出同时在线人数时显示它，没有时再显示热度或累计观看')),
              ],
            ),
          ),
          const SettingsHeader('各平台的数字是什么'),
          for (final id in platformOrder)
            if (audienceNotes[id] case final note?)
              ListTile(
                leading: PlatformLogo(platformId: id, size: 24),
                title: Text(platformNames[id] ?? id),
                subtitle: Text(note, style: theme.textTheme.bodySmall),
              ),
        ],
      ),
    );
  }
}
