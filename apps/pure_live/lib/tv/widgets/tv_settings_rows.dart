import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// A group of settings rows (docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件, rows): the group's name
/// in the primary colour (14, 600) above a card of the lowest container.
class TvSettingsGroup extends StatelessWidget {
  /// Creates the group.
  const new({required this.children, this.title, super.key});

  /// The group's name.
  final String? title;

  /// The rows.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: scale.px(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final title?)
            Padding(
              padding: EdgeInsets.only(left: scale.px(16), bottom: scale.px(8)),
              child: Text(
                title,
                style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: palette.accent),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.low,
              borderRadius: BorderRadius.circular(scale.px(TvRadius.group)),
            ),
            child: Padding(
              padding: EdgeInsets.all(scale.px(4)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// One settings row of the TV (U.15a, rows 11–14; the same parts as the
/// phone's settings row): icon, title (17), description (14, secondary,
/// up to two lines) and what is on the right. A focused row is a step
/// lighter and ringed; it does not grow (a whole row would leave the
/// screen, c2).
class TvSettingsRow extends StatelessWidget {
  /// Creates the row; [id] keys it `tv-setting-<id>`.
  const new({
    required this.id,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
    this.onKey,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The row's id.
  final String id;

  /// The title.
  final String title;

  /// The icon on the left.
  final IconData? icon;

  /// The description.
  final String? subtitle;

  /// What is on the right (a switch, a value, ›), for the focus state.
  final TvFocusBuilder? trailing;

  /// What is under the title (a slider's track).
  final Widget? below;

  /// OK.
  final VoidCallback? onTap;

  /// Keys before the default handling.
  final TvKeyHandler? onKey;

  /// The node.
  final FocusNode? focusNode;

  /// Takes the focus when first built.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return TvFocusable(
      key: ValueKey('tv-setting-$id'),
      focusNode: focusNode,
      autofocus: autofocus,
      zoom: false,
      onTap: onTap,
      onKey: onKey,
      builder: (context, focused) => Container(
        constraints: BoxConstraints(minHeight: scale.pxText(64)),
        padding: EdgeInsets.symmetric(horizontal: scale.px(16), vertical: scale.px(10)),
        decoration: BoxDecoration(
          color: focused ? palette.highest : null,
          borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: scale.pxText(24), color: palette.textSecondary),
                  SizedBox(width: scale.px(16)),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: scale.font(TvTextSize.row, color: palette.text, height: 1.35)),
                      if (subtitle case final subtitle? when subtitle.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: scale.px(2)),
                          child: Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.4),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing case final trailing?) ...[SizedBox(width: scale.px(12)), trailing(context, focused)],
              ],
            ),
            ?below,
          ],
        ),
      ),
    );
  }
}

/// The switch of a settings row: drawn, not Material's (the remote toggles
/// the row with OK or ←→; pure_live_TV's indicator).
class TvSwitchIndicator extends StatelessWidget {
  /// Creates the indicator.
  const new({required this.value, super.key});

  /// On or off.
  final bool value;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final knob = scale.px(value ? 18 : 14);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: scale.px(48),
      height: scale.px(28),
      padding: EdgeInsets.symmetric(horizontal: scale.px(value ? 3 : 5)),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: ShapeDecoration(
        color: value ? palette.accent : palette.highest,
        shape: StadiumBorder(
          side: BorderSide(color: value ? palette.accent : palette.outline, width: scale.px(2)),
        ),
      ),
      child: Container(
        width: knob,
        height: knob,
        decoration: BoxDecoration(color: value ? palette.onAccent : palette.outline, shape: BoxShape.circle),
      ),
    );
  }
}

/// A row with a switch (U.15a, row 11): OK flips it, ← switches it off and
/// → on (pure_live_TV `TvSettingsSwitchTile`); otherwise the arrow moves
/// the focus.
class TvSwitchRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.id,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
    this.autofocus = false,
    super.key,
  });

  /// The row's id.
  final String id;

  /// The title.
  final String title;

  /// On or off.
  final bool value;

  /// Sets the value.
  final ValueChanged<bool> onChanged;

  /// The icon.
  final IconData? icon;

  /// The description.
  final String? subtitle;

  /// Takes the focus when first built.
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvSettingsRow(
    id: id,
    title: title,
    icon: icon,
    subtitle: subtitle,
    autofocus: autofocus,
    onTap: () => onChanged(!value),
    onKey: (node, event) {
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft && value) {
        onChanged(false);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight && !value) {
        onChanged(true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    trailing: (context, _) => TvSwitchIndicator(value: value),
  );
}

/// A row that opens a page (U.15a, row 12): › on the right.
class TvLinkRow extends StatelessWidget {
  /// Creates the row.
  const new({required this.id, required this.title, required this.onTap, this.icon, this.subtitle, super.key});

  /// The row's id.
  final String id;

  /// The title.
  final String title;

  /// Opens the page.
  final VoidCallback onTap;

  /// The icon.
  final IconData? icon;

  /// The description.
  final String? subtitle;

  @override
  Widget build(BuildContext context) => TvSettingsRow(
    id: id,
    title: title,
    icon: icon,
    subtitle: subtitle,
    onTap: onTap,
    trailing: (context, _) =>
        Icon(TvIcons.chevron, size: TvScale.of(context).pxText(24), color: TvTheme.of(context).textSecondary),
  );
}

/// A row whose value is one of [options] (U.15a, row 13): the current value
/// and ▾ on the right; OK opens the choice dialog with the focus on the
/// current value.
class TvChoiceRow<T> extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.id,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.subtitle,
    this.autofocus = false,
    super.key,
  });

  /// The row's id.
  final String id;

  /// The title (also the dialog's).
  final String title;

  /// The current value.
  final T value;

  /// The choices.
  final List<TvChoice<T>> options;

  /// Sets the value.
  final FutureOr<void> Function(T value) onChanged;

  /// The icon.
  final IconData? icon;

  /// The description.
  final String? subtitle;

  /// Takes the focus when first built.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final index = options.indexWhere((option) => option.value == value);
    final label = index < 0 ? '$value' : options[index].label;
    return TvSettingsRow(
      id: id,
      title: title,
      icon: icon,
      subtitle: subtitle,
      autofocus: autofocus,
      onTap: () async {
        final picked = await showTvChoice<T>(context, title: title, options: options, current: value);
        if (picked != null && picked != value) await onChanged(picked);
      },
      trailing: (context, _) {
        final palette = TvTheme.of(context);
        final scale = TvScale.of(context);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: scale.font(TvTextSize.body, color: palette.textSecondary)),
            Icon(TvIcons.choice, size: scale.pxText(24), color: palette.textSecondary),
          ],
        );
      },
    );
  }
}

/// A row with a slider (U.15a, row 14): ←→ move it by [step]; at either end
/// the arrow is let through, so the focus can leave the row
/// (pure_live_TV `TvSettingsSliderTile`).
class TvSliderRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.id,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.label,
    required this.onChanged,
    this.icon,
    super.key,
  });

  /// The row's id.
  final String id;

  /// The title.
  final String title;

  /// The value.
  final double value;

  /// The lowest value.
  final double min;

  /// The highest value.
  final double max;

  /// One press of an arrow.
  final double step;

  /// The value as words ("100%").
  final String label;

  /// Sets the value.
  final ValueChanged<double> onChanged;

  /// The icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final progress = max <= min ? 0.0 : ((value - min) / (max - min)).clamp(0.0, 1.0);
    return TvSettingsRow(
      id: id,
      title: title,
      icon: icon,
      onKey: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final delta = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowLeft => -step,
          LogicalKeyboardKey.arrowRight => step,
          _ => null,
        };
        if (delta == null) return KeyEventResult.ignored;
        final next = (value + delta).clamp(min, max);
        // At an end the value no longer changes: let the arrow move on.
        if (next == value) return KeyEventResult.ignored;
        onChanged(next);
        return KeyEventResult.handled;
      },
      trailing: (context, _) => Text(label, style: scale.font(TvTextSize.body, color: palette.text).tabular),
      below: Padding(
        padding: EdgeInsets.only(top: scale.px(10)),
        child: SizedBox(
          height: scale.px(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final knob = scale.px(16);
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: scale.px(6),
                    decoration: BoxDecoration(
                      color: palette.selected,
                      borderRadius: BorderRadius.circular(scale.px(3)),
                    ),
                  ),
                  Container(
                    width: width * progress,
                    height: scale.px(6),
                    decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(scale.px(3))),
                  ),
                  Positioned(
                    left: (width * progress - knob / 2).clamp(0, width - knob),
                    child: Container(
                      width: knob,
                      height: knob,
                      decoration: BoxDecoration(color: palette.accent, shape: BoxShape.circle),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
