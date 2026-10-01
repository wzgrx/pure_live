import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The four layouts (3.x's segmented button, docs/ui/compare/U.8 c10): the
/// words alone on phones, with 3.x's icons on wide screens ([icons]).
class LayoutSegments extends StatelessWidget {
  /// Creates the segments.
  const new({required this.controller, required this.onChanged, this.icons = false, super.key});

  /// The page's controller.
  final MultiviewController controller;

  /// Called with the chosen layout.
  final ValueChanged<MultiviewLayout> onChanged;

  /// Show 3.x's icons before the words.
  final bool icons;

  static const List<(MultiviewLayout, IconData, String)> _layouts = [
    (MultiviewLayout.single, AppIcons.layoutSingle, '1×1'),
    (MultiviewLayout.dual, AppIcons.layoutDual, '1×2'),
    (MultiviewLayout.quad, AppIcons.layoutQuad, '2×2'),
    (MultiviewLayout.focus, AppIcons.layoutFocus, '1+3'),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500).tabular;
    return ListenableSelector<MultiviewLayout>(
      listenable: controller,
      selector: () => controller.layout,
      builder: (context, layout, _) => SegmentedButton<MultiviewLayout>(
        key: const ValueKey('multiview-layouts'),
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: const VisualDensity(horizontal: -2, vertical: -1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: text,
          selectedForegroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        selected: {layout},
        onSelectionChanged: (selection) => onChanged(selection.first),
        segments: [
          for (final (value, icon, label) in _layouts)
            ButtonSegment(
              value: value,
              icon: icons ? Icon(icon, size: 18) : null,
              label: Text(label, key: ValueKey('multiview-layout-${value.name}')),
            ),
        ],
      ),
    );
  }
}

/// The page's switches (docs/ui/compare/U.8 c10): danmaku on the audible
/// cell and the danmaku settings (the live room's two pictures), mute all,
/// and in the 1+3 layout the small-cell saver. One that is on has a light
/// background.
class ToolbarToggles extends StatelessWidget {
  /// Creates the switches.
  const new({required this.controller, required this.onDanmakuSettings, super.key});

  /// The page's controller.
  final MultiviewController controller;

  /// Opens (or closes) the danmaku settings panel.
  final VoidCallback onDanmakuSettings;

  @override
  Widget build(BuildContext context) => ListenableSelector<(bool, bool, bool, bool)>(
    listenable: controller,
    selector: () => (
      controller.danmakuEnabled,
      controller.allMuted,
      controller.layout == MultiviewLayout.focus,
      controller.smallCellsLowQuality,
    ),
    builder: (context, value, _) {
      final (danmaku, muted, focus, saver) = value;
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          ToolbarToggle(
            key: const ValueKey('multiview-danmaku'),
            tooltip: i18n('danmaku'),
            on: danmaku,
            onPressed: () => controller.setDanmakuEnabled(enabled: !danmaku),
            child: DanmakuIcon(danmaku ? DanmakuIconKind.on : DanmakuIconKind.off, size: 22),
          ),
          ToolbarToggle(
            key: const ValueKey('multiview-danmaku-settings'),
            tooltip: i18n('danmaku_settings'),
            on: false,
            onPressed: onDanmakuSettings,
            child: const DanmakuIcon(DanmakuIconKind.settings, size: 22),
          ),
          ToolbarToggle(
            key: const ValueKey('multiview-mute-all'),
            tooltip: i18n(muted ? 'multiview_unmute_all' : 'multiview_mute_all'),
            on: muted,
            onPressed: controller.toggleMuteAll,
            child: Icon(muted ? AppIcons.mutedAll : AppIcons.muteAll, size: 22),
          ),
          if (focus)
            ToolbarToggle(
              key: const ValueKey('multiview-saver'),
              tooltip: i18n('multiview_small_low_quality'),
              on: saver,
              onPressed: () => unawaited(controller.setSmallCellsLowQuality(enabled: !saver)),
              child: const Icon(AppIcons.smallCellSaver, size: 22),
            ),
        ],
      );
    },
  );
}

/// A round 38-point switch of the toolbar; [on] fills it with the primary
/// container colour.
class ToolbarToggle extends StatelessWidget {
  /// Creates the switch.
  const new({required this.tooltip, required this.on, required this.onPressed, required this.child, super.key});

  /// Its name (shown on hover and long press).
  final String tooltip;

  /// Switched on.
  final bool on;

  /// Called on a tap.
  final VoidCallback? onPressed;

  /// The icon.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      isSelected: on,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(38),
        minimumSize: const Size.square(38),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: on ? scheme.primaryContainer : null,
        foregroundColor: on ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
      icon: child,
    );
  }
}
