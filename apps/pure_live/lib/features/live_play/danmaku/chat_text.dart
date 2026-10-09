import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';

/// The two text roles of a chat line (docs/A-界面设计/A08-弹幕界面/A08.10-弹幕列表名字和内容分开
/// G1, G2): the sender's name and what was said. Every line that names a
/// sender uses them (compact lines, cards, local lines, gifts, the super
/// chat line, the long-press card), so a name looks the same on every
/// platform and in both list styles.
///
/// Both take the body size, so they follow the font size settings and the
/// system text scale together and share one baseline with the emoticons;
/// they differ in weight (600 and 400, UI.md §8.2) and colour.
abstract final class ChatText {
  /// What follows a name before the content ("用户名：内容"), in the name's
  /// style.
  static const String nameEnd = '：';

  /// What was said: the body size (or the list's, [sizing]), regular, the
  /// main ink.
  static TextStyle? content(ThemeData theme, {ChatSizing sizing = ChatSizing.standard}) =>
      sizing.text(theme.textTheme.bodyLarge?.regular.copyWith(color: theme.colorScheme.onSurface));

  /// The sender's name: the content's size, semibold, in [colour] (a
  /// platform's colour already made readable) or else the secondary ink.
  static TextStyle? name(ThemeData theme, [Color? colour, ChatSizing sizing = ChatSizing.standard]) =>
      sizing.text(theme.textTheme.bodyLarge?.emphasis.copyWith(color: colour ?? theme.colorScheme.onSurfaceVariant));
}

/// The chat list's text size and spacing (docs/A-界面设计/A08-弹幕界面/A08.15-聊天列表字号和行距: the
/// `danmakuListFontSize` and `danmakuListLineSpacing` settings), the
/// parameters of the [ChatText] roles and of every line's gaps and marks.
/// [standard] (0 and `standard`) is the list as it was before: every style
/// and gap comes back unchanged.
///
/// The size is the text's base size; the system text scale still applies
/// on top of it, once (the text scales itself, [chatInline] pieces through
/// their span).
@immutable
final class ChatSizing {
  /// Creates the sizing: [fontSize] 0 for the theme's body size, else the
  /// size (12..22 from the setting).
  const new({this.fontSize = 0, this.spacing = ChatSpacing.standard});

  /// The theme's size and the standard spacing.
  static const ChatSizing standard = ChatSizing();

  /// The text's size, or 0 for the theme's body size.
  final int fontSize;

  /// The gaps and the text's line height.
  final ChatSpacing spacing;

  /// The theme's chat text size (its body size).
  static double themeSize(ThemeData theme) => theme.textTheme.bodyLarge?.fontSize ?? 14;

  /// How much larger than at the theme's size the line's marks are (the
  /// chips, the badges, the gift's picture, the avatar and the dot, c3): 1
  /// at the theme's size.
  double scaleIn(ThemeData theme) => fontSize > 0 ? fontSize / themeSize(theme) : 1;

  /// [style] (a role's, at the theme's body size) at the list's size and
  /// line height; [style] itself at the standard sizing.
  TextStyle? text(TextStyle? style) {
    final height = spacing.textHeight;
    if (style == null || (fontSize <= 0 && height == null)) return style;
    return style.copyWith(fontSize: fontSize > 0 ? fontSize.toDouble() : null, height: height);
  }

  /// [style] of a smaller piece of a line (a chip's words, a gift's value)
  /// grown or shrunk with the list's size, never under 12 (UI.md §8.2);
  /// [style] itself at the theme's size.
  TextStyle? piece(TextStyle? style, ThemeData theme) {
    final size = style?.fontSize;
    if (style == null || size == null || fontSize <= 0) return style;
    return style.copyWith(fontSize: math.max(12, size * scaleIn(theme)));
  }

  /// A vertical gap of a line that is [base] at the standard spacing.
  double gap(double base) => spacing.gap(base);

  @override
  bool operator ==(Object other) => other is ChatSizing && other.fontSize == fontSize && other.spacing == spacing;

  @override
  int get hashCode => Object.hash(fontSize, spacing);
}

/// A widget inside a chat line's text (a mark before the name, the words
/// with their emoticons, a gift's count and value): laid out at the base
/// size and enlarged by the text's own scaling, like the text around it. A
/// [Text] in a plain [WidgetSpan] also reads the system scale itself and
/// came out scaled twice (A08.11: with 2x system text the words were four
/// times their size next to a name twice its size).
WidgetSpan chatInline(
  Widget child, {
  PlaceholderAlignment alignment = PlaceholderAlignment.middle,
  TextBaseline? baseline,
}) => WidgetSpan(alignment: alignment, baseline: baseline, child: ChatInline(child));

/// What [chatInline] puts in its span: [child] without the system's text
/// scaling (the span applies it).
class ChatInline extends StatelessWidget {
  /// Wraps [child].
  const new(this.child, {super.key});

  /// The widget in the line.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      // MediaQuery.withNoTextScaling, without its Builder (one widget less
      // for each piece of each line).
      MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: child,
      );
}
