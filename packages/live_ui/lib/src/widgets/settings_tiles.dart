import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/text_styles.dart';

/// Settings groups stay readable on wide desktop windows instead of
/// stretching each row across the screen; narrower layouts are unaffected.
const double settingsContentMaxWidth = 960;

/// The widest a reading column gets on large screens (settings-like pages,
/// details; docs/ui/UI_PLAN.md §5.3): one column, centred.
const double readableContentMaxWidth = 720;

/// [child] in a centred column at most [readableContentMaxWidth] wide (the
/// whole width on narrower screens).
class ReadableContent extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The column.
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: readableContentMaxWidth),
      child: child,
    ),
  );
}

/// Centred, but filling that width so a group title lines up with the left
/// edge of its card.
Widget _readableWidth(Widget child) => Align(
  alignment: Alignment.topCenter,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
    child: SizedBox(width: double.infinity, child: child),
  ),
);

/// Marks a row of [AppLayoutFactory.buildModernCard] as a tile: it gets the
/// card's rounded corners and dividers like a [ListTile].
///
/// Tiles from [AppLayoutFactory.buildTile] and
/// [AppLayoutFactory.buildSwitchTile] are marked already; wrap a tile that a
/// builder (a provider consumer, a stream) produces.
class CardTile extends StatelessWidget {
  /// Marks [child].
  const new({required this.child, super.key});

  /// The tile.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

bool _isTile(Widget widget) =>
    widget is CardTile ||
    widget is ListTile ||
    widget is SwitchListTile ||
    widget is CheckboxListTile ||
    widget is RadioListTile ||
    widget is ExpansionTile;

/// The settings page building blocks of 3.x (`AppLayoutFactory`): group
/// titles, rounded cards of tiles, switch, navigation and slider rows.
extension AppLayoutFactory on BuildContext {
  /// A group title above a card.
  Widget buildGroupTitle(String text) {
    final theme = Theme.of(this);
    return _readableWidth(
      Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 8),
        child: Text(
          text,
          style: AppTextStyles(theme).t12.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary.withValues(alpha: 0.65),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  /// A rounded card of rows. Tiles (see [CardTile]) get the card's corner
  /// shape and a faint divider between neighbouring tiles; [SizedBox]es are
  /// dropped (3.x callers used them as conditional placeholders).
  Widget buildModernCard(List<Widget> children) {
    final theme = Theme.of(this);
    final rows = children.where((widget) => widget is! SizedBox).toList();
    final shaped = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final child = rows[i];
      final isTile = _isTile(child);
      if (isTile) {
        final ShapeBorder shape;
        if (rows.length == 1) {
          shape = const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20)));
        } else if (i == 0) {
          shape = const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20)));
        } else if (i == rows.length - 1) {
          shape = const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)));
        } else {
          shape = LinearBorder.none;
        }
        shaped.add(ListTileTheme.merge(shape: shape, child: child));
      } else {
        shaped.add(child);
      }
      if (isTile && i < rows.length - 1 && _isTile(rows[i + 1])) {
        shaped.add(
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 16,
            endIndent: 16,
            color: theme.dividerColor.withValues(alpha: 0.05),
          ),
        );
      }
    }
    return _readableWidth(
      Material(
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.05), width: 0.5),
        ),
        child: Column(children: shaped),
      ),
    );
  }

  Widget? _subtitle(String? subtitle, {required Color? color, required bool isLong}) {
    if (subtitle == null || subtitle.isEmpty) return null;
    final theme = Theme.of(this);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        subtitle,
        style: AppTextStyles(theme).t12.copyWith(color: color ?? theme.hintColor.withValues(alpha: 0.75)),
        maxLines: isLong ? null : 1,
        overflow: isLong ? TextOverflow.visible : TextOverflow.ellipsis,
      ),
    );
  }

  /// A switch row. [onChanged] receives the new value; the caller stores it
  /// (3.x wrote it into a reactive value itself). Disabled when [enabled] is
  /// false or [onChanged] is null.
  Widget buildSwitchTile({
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
    IconData? icon,
    String? subtitle,
    Color? iconColor,
    Color? subtitleColor,
    bool isLong = false,
    bool enabled = true,
    Key? key,
  }) {
    final theme = Theme.of(this);
    return CardTile(
      key: key,
      child: SwitchListTile(
        secondary: icon != null ? Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 22) : null,
        title: Text(title, style: AppTextStyles(theme).t15.copyWith(fontWeight: FontWeight.w600)),
        subtitle: _subtitle(subtitle, color: subtitleColor, isLong: isLong),
        value: value,
        onChanged: enabled ? onChanged : null,
        contentPadding: const EdgeInsets.only(left: 16, top: 2, bottom: 2, right: 8),
      ),
    );
  }

  /// A row with an icon, title, text and a trailing widget; with [onTap] and
  /// no trailing widget it shows a chevron. With [stackTrailingOnNarrow] the
  /// trailing widget moves under the text below 360 px or above 1.5× text.
  Widget buildTile({
    required String title,
    IconData? icon,
    Widget? iconWidget,
    String? subtitle,
    VoidCallback? onTap,
    Color? iconColor,
    Color? subtitleColor,
    Widget? trailing,
    bool isLong = false,
    bool stackTrailingOnNarrow = false,
    bool showNavigationChevronWhenStacked = true,
    Key? key,
  }) {
    final theme = Theme.of(this);
    final color = iconColor ?? theme.colorScheme.primary;
    final leadingIcon = iconWidget != null
        ? IconTheme(
            data: IconThemeData(color: color, size: 22),
            child: iconWidget,
          )
        : (icon != null ? Icon(icon, color: color, size: 22) : null);
    final leading = leadingIcon == null
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [Padding(padding: const EdgeInsets.only(top: 2), child: leadingIcon)],
          );
    final titleWidget = Text(title, style: AppTextStyles(theme).t15.copyWith(fontWeight: FontWeight.w600));
    final subtitleWidget = _subtitle(subtitle, color: subtitleColor, isLong: isLong);
    final chevron = Icon(Icons.chevron_right_rounded, color: theme.hintColor.withValues(alpha: 0.4), size: 20);

    Widget standardTile() => ListTile(
      horizontalTitleGap: 12,
      minLeadingWidth: 0,
      minVerticalPadding: 0,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: leading,
      title: titleWidget,
      subtitle: subtitleWidget,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsets.only(top: 4), child: trailing ?? (onTap != null ? chevron : null)),
        ],
      ),
      onTap: onTap,
    );

    if (!stackTrailingOnNarrow || trailing == null) return CardTile(key: key, child: standardTile());
    return CardTile(
      key: key,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          if (constraints.maxWidth >= 360 && textScale <= 1.5) return standardTile();
          return ListTile(
            horizontalTitleGap: 12,
            minLeadingWidth: 0,
            minVerticalPadding: 0,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: leading,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleWidget, ?subtitleWidget, const SizedBox(height: 8), trailing],
            ),
            trailing: onTap != null && showNavigationChevronWhenStacked ? chevron : null,
            onTap: onTap,
          );
        },
      ),
    );
  }

  /// A slider row: icon, title with the value in a badge (under the title
  /// when both do not fit on one line), optional text, then the slider.
  Widget buildSliderTile({
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    String? subtitle,
  }) {
    final theme = Theme.of(this);
    final styles = AppTextStyles(theme);
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(width: 24, child: Icon(icon, size: 22, color: primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SliderHeading(
                  title: title,
                  value: displayValue,
                  titleStyle: styles.t16.copyWith(fontWeight: FontWeight.w600),
                  valueStyle: styles.t13.copyWith(fontWeight: FontWeight.bold, color: primary),
                  badgeColor: primary.withValues(alpha: 0.1),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: styles.t12.copyWith(color: theme.hintColor.withValues(alpha: 0.75))),
                ],
                const SizedBox(height: 2),
                Transform.translate(
                  offset: const Offset(-4, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: SliderTheme(
                      data: settingsSliderTheme(theme),
                      child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The settings slider's look: 3.x drew Syncfusion's slider (a 6 px active
/// and 4 px inactive track, a 10 px round thumb in the primary colour);
/// Flutter's slider is shaped the same so the proprietary package can go.
SliderThemeData settingsSliderTheme(ThemeData theme) {
  final primary = theme.colorScheme.primary;
  return SliderThemeData(
    trackHeight: 4,
    activeTrackColor: primary,
    inactiveTrackColor: primary.withValues(alpha: 0.15),
    thumbColor: primary,
    overlayColor: primary.withValues(alpha: 0.12),
    trackShape: const RoundedRectSliderTrackShape(),
    thumbShape: const RoundSliderThumbShape(elevation: 0, pressedElevation: 0),
    overlayShape: const RoundSliderOverlayShape(),
    showValueIndicator: ShowValueIndicator.never,
  );
}

class _SliderHeading extends StatelessWidget {
  const new({
    required this.title,
    required this.value,
    required this.titleStyle,
    required this.valueStyle,
    required this.badgeColor,
  });

  final String title;
  final String value;
  final TextStyle titleStyle;
  final TextStyle valueStyle;
  final Color badgeColor;

  double _width(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    // 3.x never disposed these painters, leaking their paragraphs.
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
      child: Text(value, style: valueStyle),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits =
            _width(context, title, titleStyle) + _width(context, value, valueStyle) + 28 <= constraints.maxWidth;
        if (fits) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: titleStyle)),
              const SizedBox(width: 12),
              badge,
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: titleStyle),
            const SizedBox(height: 6),
            badge,
          ],
        );
      },
    );
  }
}

/// A section heading in the primary colour (3.x `SectionTitle`).
class SectionTitle extends StatelessWidget {
  /// Creates the heading.
  const new({required this.title, super.key});

  /// The text.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        title,
        style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// A popup menu entry: icon, label and an optional trailing widget (3.x
/// `MenuListTile`).
class MenuListTile extends StatelessWidget {
  /// Creates the entry.
  const new({required this.leading, required this.text, this.trailing, super.key});

  /// Icon.
  final Widget? leading;

  /// Label.
  final String text;

  /// Trailing widget.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading case final leading?) ...[leading, const SizedBox(width: 12)],
        Text(text, style: Theme.of(context).textTheme.labelMedium),
        if (trailing case final trailing?) ...[const SizedBox(width: 24), trailing],
      ],
    );
  }
}
