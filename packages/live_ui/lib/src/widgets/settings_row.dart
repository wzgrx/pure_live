import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/live_theme.dart';
import 'package:live_ui/src/theme/metrics.dart';
import 'package:live_ui/src/theme/text_wrapping.dart';
import 'package:live_ui/src/widgets/app_chip.dart';
import 'package:live_ui/src/widgets/count_button.dart';

// The settings row of every settings page (docs/A-界面设计/A11-设置界面/A11.1-设置总览, "设置行";
// U.1c c14–c17): one look for link, switch, choice, slider and counter rows,
// with pressed, keyboard-focus, hover, disabled and busy states. 3.x had
// four builders (`buildTile`, `buildSwitchTile`, `buildMenuTile`,
// `buildSliderTile`) plus pages that drew their own; its explanations showed
// one line at about 3.4:1. Here the explanation is the theme's
// `onSurfaceVariant` on `surfaceContainerLow` (above 4.5:1 in every Material
// scheme) and wraps to two lines; the title is 15 regular (U.1c C3, the
// weight of U.2f's panel rows).

/// The width under which, or the text scale above which, a row's value
/// moves under its title (3.x `stackTrailingOnNarrow`).
const double settingsRowNarrowWidth = 360;

/// Text scale from which a row's value moves under its title.
const double settingsRowLargeText = 1.5;

/// The size of a row's value and a counter's number: the emphasised body
/// size (14 by default), one step larger on the television (16, UI.md
/// §5.5).
double settingsValueFontSize(BuildContext context, {required bool tv}) {
  final size = LiveFontSizes.of(Theme.of(context).textTheme).bodyLarge;
  return tv ? size * 16 / 14 : size;
}

/// How settings rows look in a subtree: the phone and desktop style, or the
/// television style (focus enlarges the row and draws a near-white frame,
/// text one step larger; UI_PLAN §5.5).
class SettingsRowStyle extends InheritedWidget {
  /// Applies [tv] to [child].
  const new({required this.tv, required super.child, super.key});

  /// The television style.
  final bool tv;

  /// Whether rows under [context] use the television style.
  static bool tvOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsRowStyle>()?.tv ?? false;

  @override
  bool updateShouldNotify(SettingsRowStyle oldWidget) => oldWidget.tv != tv;
}

/// Words searched for: rows under it mark them in their title and
/// explanation (the settings search).
class SettingsHighlight extends InheritedWidget {
  /// Marks [words] (lower case) under [child].
  const new({required this.words, required super.child, super.key});

  /// The words, lower case, not empty.
  final List<String> words;

  /// The words in scope, or none.
  static List<String> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsHighlight>()?.words ?? const [];

  @override
  bool updateShouldNotify(SettingsHighlight oldWidget) => oldWidget.words.join(' ') != words.join(' ');
}

/// [text] with [words] marked in a soft primary background; an
/// [explanation] never ends with a line of one character ([withoutOrphan]).
class HighlightedText extends StatelessWidget {
  /// Creates the text.
  const new(this.text, {required this.style, this.maxLines, this.words, this.explanation = false, super.key});

  /// The text.
  final String text;

  /// Its style.
  final TextStyle style;

  /// Lines before an ellipsis.
  final int? maxLines;

  /// Words to mark; [SettingsHighlight.of] when null.
  final List<String>? words;

  /// Whether [text] is an explanation (no one-character last line).
  final bool explanation;

  @override
  Widget build(BuildContext context) {
    final marks = words ?? SettingsHighlight.of(context);
    final overflow = maxLines == null ? null : TextOverflow.ellipsis;
    final text = explanation ? withoutOrphan(this.text) : this.text;
    if (marks.isEmpty) return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    // The joiner is no letter: words match across it.
    final lower = text.toLowerCase().replaceAll(wordJoiner, '\u0000');
    final joined = lower.indexOf('\u0000');
    final plain = joined < 0 ? lower : lower.replaceFirst('\u0000', '');
    final found = List<bool>.filled(plain.length, false);
    for (final word in marks) {
      if (word.isEmpty) continue;
      var from = 0;
      while (true) {
        final at = plain.indexOf(word, from);
        if (at < 0 || at + word.length > plain.length) break;
        for (var i = at; i < at + word.length; i++) {
          found[i] = true;
        }
        from = at + word.length;
      }
    }
    final marked = joined < 0
        ? found
        : [...found.take(joined), found.length > joined && found[joined], ...found.skip(joined)];
    final background = Theme.of(context).colorScheme.primary.withValues(alpha: 0.22);
    final spans = <TextSpan>[];
    var start = 0;
    for (var i = 1; i <= text.length; i++) {
      if (i == text.length || marked[i] != marked[start]) {
        spans.add(
          TextSpan(
            text: text.substring(start, i),
            style: marked[start] ? TextStyle(backgroundColor: background) : null,
          ),
        );
        start = i;
      }
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// A titled group of rows on one rounded card (U.6a: title 13 px semi-bold
/// in the primary colour, card 16 px corners on `surfaceContainerLow`, a
/// divider between rows that starts where the text starts).
class SettingsGroup extends StatelessWidget {
  /// Creates the group.
  const new({
    required this.children,
    this.title,
    this.note,
    this.footer,
    this.footerWidget,
    this.first = false,
    this.card = true,
    super.key,
  });

  /// Something under the card other than a line of text (a note with a
  /// link).
  final Widget? footerWidget;

  /// Whether the children sit on the card; false lays them out as they are
  /// (chips, a preview) under the title.
  final bool card;

  /// The group title; none draws only the card.
  final String? title;

  /// A line between the title and the card (how to use the group).
  final String? note;

  /// A line under the card.
  final String? footer;

  /// The first group of a page (less space above the title).
  final bool first;

  /// The rows.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final divider = Padding(
      padding: const EdgeInsetsDirectional.only(start: 56),
      child: Divider(height: 1, thickness: 1, color: colors.outlineVariant.withValues(alpha: 0.7)),
    );
    final rows = <Widget>[];
    for (final (index, child) in children.indexed) {
      if (index > 0) rows.add(divider);
      rows.add(child);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final title?) SettingsGroupTitle(title, first: first),
        if (note case final note?) SettingsNote(note, padding: const EdgeInsets.fromLTRB(8, 0, 8, 12)),
        if (!card)
          ...children
        else
          // A Material, so list tiles on it (the platform accounts) keep
          // their ink.
          Material(
            color: colors.surfaceContainerLow,
            borderRadius: AppRadii.card,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        if (footer case final footer?) SettingsNote(footer),
        ?footerWidget,
      ],
    );
  }
}

/// A group's title (U.6a, U.1c c15): 13 points, semi-bold, the primary
/// colour without transparency (3.x's 65 % was about 2.9:1); for a group
/// whose card is laid out by the page (a reorderable list).
class SettingsGroupTitle extends StatelessWidget {
  /// Creates the title.
  const new(this.text, {this.first = false, this.padding, super.key});

  /// The words.
  final String text;

  /// The first group of a page (less space above).
  final bool first;

  /// Space around the words; null is the group's.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? EdgeInsetsDirectional.fromSTEB(16, first ? 8 : 18, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
            // The body size; the TV's one step larger (15 by default).
            fontSize: SettingsRowStyle.tvOf(context) ? LiveFontSizes.of(theme.textTheme).bodyMedium * 15 / 13 : null,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// A line of explanation under or above a group (12 px, secondary colour).
class SettingsNote extends StatelessWidget {
  /// Creates the line.
  const new(this.text, {this.padding = const EdgeInsets.fromLTRB(8, 12, 8, 0), super.key});

  /// The text.
  final String text;

  /// Space around it.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        withoutOrphan(text),
        style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
          // The small size; the TV's one step larger (14 by default).
          fontSize: SettingsRowStyle.tvOf(context) ? LiveFontSizes.of(theme.textTheme).bodySmall * 14 / 12 : null,
          height: 1.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The frame every row kind shares: icon, title, explanation, something at
/// the end and optionally something below; the states.
class SettingsRow extends StatefulWidget {
  /// Creates a row; most pages use the named kinds ([SettingsLinkRow],
  /// [SettingsSwitchRow], [SettingsSliderRow], [SettingsCounterRow],
  /// [SettingsChipsRow]).
  const new({
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.subtitleColor,
    this.titleColor,
    this.trailing,
    this.stackTrailing = true,
    this.below,
    this.onTap,
    this.enabled = true,
    this.disabledReason,
    this.busy = false,
    this.busyColor,
    this.selected = false,
    this.tooltip,
    this.subtitleMaxLines = 3,
    this.keepTrailingWhileBusy = false,
    super.key,
  });

  /// The title.
  final String title;

  /// While [busy], shows the spinner before [trailing] (which greys itself
  /// out) instead of replacing it (a switch that is being changed, U.1c).
  final bool keepTrailingWhileBusy;

  /// The spinner's colour while [busy] (error red for clearing).
  final Color? busyColor;

  /// Lines of the explanation before an ellipsis; null shows it whole (a
  /// folder path, a long explanation).
  final int? subtitleMaxLines;

  /// The icon at the start (22 px, primary colour).
  final IconData? icon;

  /// A widget instead of [icon] (a live preview, a picture).
  final Widget? leading;

  /// The explanation (at most three lines, A01.4 c2).
  final String? subtitle;

  /// The explanation's colour when it reports a problem (error red).
  final Color? subtitleColor;

  /// The title's colour for a destructive action (error red: "清空本地缓存",
  /// "恢复默认设置").
  final Color? titleColor;

  /// Shown at the end (value, switch, swatch, counter).
  final Widget? trailing;

  /// Whether [trailing] moves under the text on narrow rows or large text
  /// (values and counters do; a switch stays at the end).
  final bool stackTrailing;

  /// Shown under the title row, aligned with the text (slider, chips).
  final Widget? below;

  /// The row's action; null makes the row not tappable.
  final VoidCallback? onTap;

  /// False greys the row out and ignores taps; [disabledReason] replaces
  /// the explanation.
  final bool enabled;

  /// Why the row cannot be used now.
  final String? disabledReason;

  /// Working: a spinner at the end, taps ignored.
  final bool busy;

  /// The current item of a list (the left pane of the wide settings).
  final bool selected;

  /// A hint on hover (desktop).
  final String? tooltip;

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _focused = false;

  bool get _keyboard => FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tv = SettingsRowStyle.tvOf(context);
    final usable = widget.enabled && !widget.busy;
    final body = theme.textTheme.bodyMedium ?? const TextStyle();
    // The card title and small sizes; the TV's one step larger (UI.md §5.5:
    // 17 and 14 by default).
    final sizes = LiveFontSizes.of(theme.textTheme);
    final titleStyle = body.copyWith(
      fontSize: tv ? sizes.titleMedium * 17 / 15 : sizes.titleMedium,
      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
      height: 1.4,
      color: widget.titleColor ?? (widget.selected ? colors.onSecondaryContainer : colors.onSurface),
    );
    final subtitleStyle = body.copyWith(
      fontSize: tv ? sizes.bodySmall * 14 / 12 : sizes.bodySmall,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: widget.subtitleColor ?? colors.onSurfaceVariant,
    );
    final subtitle = !widget.enabled && widget.disabledReason != null ? widget.disabledReason : widget.subtitle;
    final leading =
        widget.leading ??
        (widget.icon == null
            ? null
            : Icon(widget.icon, size: tv ? 24 : 22, color: widget.titleColor ?? colors.primary));
    final spinner = SizedBox.square(
      key: const ValueKey('settings-row-busy'),
      dimension: 24,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: CircularProgressIndicator(strokeWidth: 2.5, color: widget.busyColor ?? colors.primary),
      ),
    );
    final trailing = !widget.busy
        ? widget.trailing
        : widget.keepTrailingWhileBusy && widget.trailing != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            // The trailing control shows itself unusable (a disabled switch).
            children: [spinner, widget.trailing!],
          )
        : spinner;

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HighlightedText(widget.title, style: titleStyle),
        if (subtitle != null && subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: HighlightedText(
              subtitle,
              style: subtitleStyle,
              maxLines: widget.subtitleMaxLines,
              explanation: true,
            ),
          ),
      ],
    );

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final stack =
            widget.stackTrailing &&
            trailing != null &&
            (constraints.maxWidth < settingsRowNarrowWidth || scale >= settingsRowLargeText);
        final start = leading == null
            ? null
            : SizedBox(
                width: tv ? 28 : 24,
                child: Center(child: leading),
              );
        return Padding(
          padding: EdgeInsetsDirectional.fromSTEB(16, 10, 12, widget.below == null ? 10 : 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: subtitle == null || subtitle.isEmpty ? 36 : 44),
                child: Row(
                  children: [
                    if (start != null) ...[start, const SizedBox(width: 16)],
                    Expanded(
                      child: stack
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [text, const SizedBox(height: 6), trailing],
                            )
                          : text,
                    ),
                    if (!stack && trailing != null) ...[const SizedBox(width: 12), trailing],
                  ],
                ),
              ),
              if (widget.below case final below?)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: start == null ? 0 : (tv ? 44 : 40)),
                  child: below,
                ),
            ],
          ),
        );
      },
    );

    final overlay = colors.onSurface;
    Widget row = Material(
      color: widget.selected ? colors.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: usable ? widget.onTap : null,
        canRequestFocus: usable && widget.onTap != null,
        hoverColor: overlay.withValues(alpha: 0.06),
        highlightColor: overlay.withValues(alpha: 0.10),
        focusColor: overlay.withValues(alpha: 0.04),
        splashFactory: NoSplash.splashFactory,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: content,
      ),
    );

    final showRing = _focused && (_keyboard || tv);
    row = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: AppRadii.listRow,
        border: showRing ? Border.all(color: tv ? LiveTvColors.focusFrame : colors.primary, width: tv ? 3 : 2) : null,
      ),
      child: row,
    );
    if (tv) row = AnimatedScale(scale: _focused ? 1.05 : 1, duration: AppDurations.fast, child: row);
    if (widget.tooltip case final tooltip?) row = Tooltip(message: tooltip, child: row);
    if (!widget.enabled) {
      row = Opacity(
        opacity: 0.38,
        child: IgnorePointer(child: ExcludeFocus(child: row)),
      );
    }
    return Semantics(enabled: usable, selected: widget.selected, child: row);
  }
}

/// A row that opens something: a page, a dialog of choices, a colour. The
/// current value (14 px, secondary colour) or [valueWidget] (a swatch) sits
/// before the mark at the end: › for a page, ⌄ for a dialog of choices
/// ([choice], U.1c C2).
class SettingsLinkRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.title,
    required this.onTap,
    this.icon,
    this.leading,
    this.subtitle,
    this.subtitleColor,
    this.value,
    this.valueWidget,
    this.valueBelow = false,
    this.chevron = true,
    this.choice = false,
    this.enabled = true,
    this.disabledReason,
    this.busy = false,
    this.selected = false,
    this.tooltip,
    this.subtitleMaxLines = 3,
    super.key,
  });

  /// The title.
  final String title;

  /// See [SettingsRow.subtitleMaxLines].
  final int? subtitleMaxLines;

  /// The action.
  final VoidCallback? onTap;

  /// Shows [value] under the explanation in the primary colour instead of
  /// at the end (long values such as "跟随直播源（推荐）", U.6c c6).
  final bool valueBelow;

  /// The icon.
  final IconData? icon;

  /// A widget instead of [icon].
  final Widget? leading;

  /// The explanation.
  final String? subtitle;

  /// The explanation's colour when it reports a problem.
  final Color? subtitleColor;

  /// The current value.
  final String? value;

  /// A widget instead of [value] (a colour swatch).
  final Widget? valueWidget;

  /// Whether the mark at the end (› or ⌄) shows.
  final bool chevron;

  /// The row picks one of a few values in a dialog: ⌄ instead of ›.
  final bool choice;

  /// See [SettingsRow.enabled].
  final bool enabled;

  /// See [SettingsRow.disabledReason].
  final String? disabledReason;

  /// See [SettingsRow.busy].
  final bool busy;

  /// See [SettingsRow.selected].
  final bool selected;

  /// See [SettingsRow.tooltip].
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tv = SettingsRowStyle.tvOf(context);
    final value = this.value;
    final below = valueBelow && value != null && value.isNotEmpty;
    final trailing = <Widget>[
      ?valueWidget,
      if (!below && value != null && value.isNotEmpty)
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
              fontSize: settingsValueFontSize(context, tv: tv),
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      if (chevron)
        Icon(choice ? AppIcons.choiceRow : AppIcons.navigate, size: choice ? 20 : 24, color: colors.onSurfaceVariant),
    ];
    return SettingsRow(
      title: title,
      icon: icon,
      leading: leading,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      enabled: enabled,
      disabledReason: disabledReason,
      busy: busy,
      selected: selected,
      tooltip: tooltip,
      subtitleMaxLines: subtitleMaxLines,
      onTap: onTap,
      // Only a value moves under the title when narrow; a lone chevron stays
      // at the end (the settings list beside its page is under 360 wide, A04.1).
      stackTrailing: valueWidget != null || (!below && value != null && value.isNotEmpty),
      below: below
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                value,
                style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
                  fontSize: settingsValueFontSize(context, tv: tv),
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            )
          : null,
      trailing: trailing.isEmpty
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: trailing),
            ),
    );
  }
}

/// A switch row: a tap anywhere on the row switches it.
class SettingsSwitchRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.leading,
    this.subtitle,
    this.subtitleColor,
    this.enabled = true,
    this.disabledReason,
    this.busy = false,
    this.subtitleMaxLines = 3,
    super.key,
  });

  /// The title.
  final String title;

  /// See [SettingsRow.subtitleMaxLines].
  final int? subtitleMaxLines;

  /// On or off.
  final bool value;

  /// Receives the new value; null disables the row.
  final ValueChanged<bool>? onChanged;

  /// The icon.
  final IconData? icon;

  /// A widget instead of [icon].
  final Widget? leading;

  /// The explanation.
  final String? subtitle;

  /// The explanation's colour when it reports a problem.
  final Color? subtitleColor;

  /// See [SettingsRow.enabled].
  final bool enabled;

  /// See [SettingsRow.disabledReason].
  final String? disabledReason;

  /// See [SettingsRow.busy].
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final usable = enabled && onChanged != null && !busy;
    return SettingsRow(
      title: title,
      icon: icon,
      leading: leading,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      enabled: enabled && onChanged != null,
      disabledReason: disabledReason,
      busy: busy,
      keepTrailingWhileBusy: true,
      subtitleMaxLines: subtitleMaxLines,
      stackTrailing: false,
      onTap: usable ? () => onChanged!(!value) : null,
      // The row takes the taps and the focus; the switch only shows the
      // state (Material 3's default colours: an on switch has a light thumb
      // on the primary track, so the thumb stays visible, U.4f).
      trailing: ExcludeFocus(
        child: IgnorePointer(
          child: Switch(value: value, onChanged: usable ? (_) {} : null),
        ),
      ),
    );
  }
}

/// A slider row: the value in a pill at the end, the slider under the text.
/// The page stores the value when the drag ends (or a short pause).
class SettingsSliderRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.marks = const [],
    this.icon,
    this.leading,
    this.subtitle,
    this.below,
    this.enabled = true,
    this.disabledReason,
    super.key,
  });

  /// The title.
  final String title;

  /// The value shown.
  final double value;

  /// The range.
  final double min;

  /// The range.
  final double max;

  /// The pill's text ("100%", "12px").
  final String label;

  /// Every move.
  final ValueChanged<double>? onChanged;

  /// The end of a drag.
  final ValueChanged<double>? onChangeEnd;

  /// Steps of the slider.
  final int? divisions;

  /// Values marked on the track (the usual stops).
  final List<double> marks;

  /// The icon.
  final IconData? icon;

  /// A widget instead of [icon].
  final Widget? leading;

  /// The explanation.
  final String? subtitle;

  /// Shown under the slider (an example text).
  final Widget? below;

  /// See [SettingsRow.enabled].
  final bool enabled;

  /// See [SettingsRow.disabledReason].
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          label,
          style: (theme.textTheme.bodyMedium ?? const TextStyle()).tabular.copyWith(
            fontSize: SettingsRowStyle.tvOf(context) ? LiveFontSizes.of(theme.textTheme).bodyMedium * 15 / 13 : null,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
      ),
    );
    final span = max - min;
    final slider = SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.primary.withValues(alpha: 0.18),
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(elevation: 0, pressedElevation: 0),
        tickMarkShape: SliderTickMarkShape.noTickMark,
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (marks.isNotEmpty && span > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  // Material's slider keeps the overlay radius (24) free at
                  // both ends.
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        for (final mark in marks)
                          Positioned(
                            left: constraints.maxWidth * ((mark - min) / span).clamp(0, 1) - 3,
                            top: constraints.maxHeight / 2 - 3,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? onChangeEnd : null,
          ),
        ],
      ),
    );
    return SettingsRow(
      title: title,
      icon: icon,
      leading: leading,
      subtitle: subtitle,
      enabled: enabled,
      disabledReason: disabledReason,
      stackTrailing: false,
      trailing: pill,
      below: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Transform.translate(offset: const Offset(-14, 0), child: slider),
          ?below,
        ],
      ),
    );
  }
}

/// A counter row: the outlined [CounterControl] at the end; − and + change
/// the value by one step (held, they repeat), the number opens a field to
/// type it ([onValueTap]).
class SettingsCounterRow extends StatefulWidget {
  /// Creates the row.
  const new({
    required this.title,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.decreaseTooltip,
    required this.increaseTooltip,
    this.onValueTap,
    this.icon,
    this.leading,
    this.subtitle,
    this.enabled = true,
    this.disabledReason,
    this.valueKey,
    this.decreaseKey,
    this.increaseKey,
    this.subtitleMaxLines = 3,
    super.key,
  });

  /// The title.
  final String title;

  /// See [SettingsRow.subtitleMaxLines].
  final int? subtitleMaxLines;

  /// The value as shown ("6 px").
  final String value;

  /// One step down; null at the minimum.
  final VoidCallback? onDecrease;

  /// One step up; null at the maximum.
  final VoidCallback? onIncrease;

  /// The − button's name.
  final String decreaseTooltip;

  /// The + button's name.
  final String increaseTooltip;

  /// A tap on the number.
  final VoidCallback? onValueTap;

  /// The icon.
  final IconData? icon;

  /// A widget instead of [icon].
  final Widget? leading;

  /// The explanation.
  final String? subtitle;

  /// See [SettingsRow.enabled].
  final bool enabled;

  /// See [SettingsRow.disabledReason].
  final String? disabledReason;

  /// Keys of the number and the buttons (tests).
  final Key? valueKey;

  /// Key of the − button.
  final Key? decreaseKey;

  /// Key of the + button.
  final Key? increaseKey;

  @override
  State<SettingsCounterRow> createState() => _SettingsCounterRowState();
}

class _SettingsCounterRowState extends State<SettingsCounterRow> {
  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    return SettingsRow(
      title: widget.title,
      icon: widget.icon,
      leading: widget.leading,
      subtitle: widget.subtitle,
      enabled: widget.enabled,
      disabledReason: widget.disabledReason,
      subtitleMaxLines: widget.subtitleMaxLines,
      trailing: CounterControl(
        value: widget.value,
        semanticLabel: widget.title,
        decreaseTooltip: widget.decreaseTooltip,
        increaseTooltip: widget.increaseTooltip,
        onDecrease: widget.onDecrease,
        onIncrease: widget.onIncrease,
        onValueTap: widget.onValueTap,
        enabled: widget.enabled,
        valueKey: widget.valueKey,
        decreaseKey: widget.decreaseKey,
        increaseKey: widget.increaseKey,
      ),
    );
  }
}

/// One short option of a [SettingsChipsRow].
typedef SettingsChip<T> = ({T value, String label, Key? key});

/// Two or three short options laid out on the row (3.x's room card layout
/// and platform badge); the chosen one is filled and ticked.
class SettingsChipsRow<T> extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.subtitle,
    this.enabled = true,
    super.key,
  });

  /// The title.
  final String title;

  /// The options.
  final List<SettingsChip<T>> options;

  /// The current option.
  final T? selected;

  /// Receives the picked option.
  final ValueChanged<T>? onSelected;

  /// The icon.
  final IconData? icon;

  /// The explanation.
  final String? subtitle;

  /// See [SettingsRow.enabled].
  final bool enabled;

  @override
  Widget build(BuildContext context) => SettingsRow(
    title: title,
    icon: icon,
    subtitle: subtitle,
    enabled: enabled,
    below: Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: SettingsChoiceChips<T>(options: options, selected: selected, onSelected: onSelected),
    ),
  );
}

/// The chips of [SettingsChipsRow], also used alone (presets).
class SettingsChoiceChips<T> extends StatelessWidget {
  /// Creates the chips.
  const new({required this.options, required this.selected, required this.onSelected, super.key});

  /// The options.
  final List<SettingsChip<T>> options;

  /// The current option.
  final T? selected;

  /// Receives the picked option.
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final option in options)
        AppChip(
          key: option.key,
          label: option.label,
          selected: option.value == selected,
          onSelected: onSelected == null ? null : () => onSelected!(option.value),
        ),
    ],
  );
}

/// A round colour swatch at the end of a colour row (28 px).
class SettingsSwatch extends StatelessWidget {
  /// Creates the swatch.
  const new(this.color, {this.size = 28, super.key});

  /// The colour.
  final Color color;

  /// Its diameter.
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}

/// The settings search field (48 high, round): search icon, text, clear.
class SettingsSearchField extends StatelessWidget {
  /// Creates the field.
  const new({
    required this.controller,
    required this.hint,
    required this.clearTooltip,
    this.focusNode,
    this.fieldKey,
    this.clearKey,
    super.key,
  });

  /// The text.
  final TextEditingController controller;

  /// The empty field's hint ("搜索设置").
  final String hint;

  /// The clear button's name.
  final String clearTooltip;

  /// The focus (Ctrl+F moves it here).
  final FocusNode? focusNode;

  /// Key of the text field.
  final Key? fieldKey;

  /// Key of the clear button.
  final Key? clearKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final size = theme.textTheme.titleMedium?.fontSize;
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) => SizedBox(
        height: 48,
        child: TextField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: size, color: colors.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: size, color: colors.onSurfaceVariant),
            filled: true,
            fillColor: colors.surfaceContainerHigh,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            prefixIcon: Icon(AppIcons.searchField, size: 22, color: colors.onSurfaceVariant),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    key: clearKey,
                    tooltip: clearTooltip,
                    icon: Icon(AppIcons.clearQuery, size: 20, color: colors.onSurfaceVariant),
                    onPressed: controller.clear,
                  ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
              borderSide: BorderSide.none,
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(24)),
              borderSide: BorderSide(color: colors.primary, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
