import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';

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

  /// What was said: the body size, regular, the main ink.
  static TextStyle? content(ThemeData theme) =>
      theme.textTheme.bodyLarge?.regular.copyWith(color: theme.colorScheme.onSurface);

  /// The sender's name: the content's size, semibold, in [colour] (a
  /// platform's colour already made readable) or else the secondary ink.
  static TextStyle? name(ThemeData theme, [Color? colour]) =>
      theme.textTheme.bodyLarge?.emphasis.copyWith(color: colour ?? theme.colorScheme.onSurfaceVariant);
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
      MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling), child: child);
}
